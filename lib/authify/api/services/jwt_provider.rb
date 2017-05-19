module Authify
  module API
    module Services
      # A Sinatra App specifically for managing JWT tokens
      class JWTProvider < Service
        use Authify::API::Middleware::Metrics

        helpers Helpers::APIUser

        configure do
          set :protection, except: :http_origin
        end

        before '*' do
          content_type 'application/json'
          headers 'Access-Control-Allow-Origin' => '*',
                  'Access-Control-Allow-Methods' => %w[
                    OPTIONS
                    GET
                    POST
                  ]

          begin
            unless request.get? || request.options?
              request.body.rewind
              @parsed_body = JSON.parse(request.body.read, symbolize_names: true)
            end
          rescue => e
            halt(400, { error: "Request must be valid JSON: #{e.message}" }.to_json)
          end
        end

        post '/token' do
          # For CLI / Typical API clients
          access = @parsed_body[:access_key] || @parsed_body[:'access-key']
          secret = @parsed_body[:secret_key] || @parsed_body[:'secret-key']
          # For Web UIs
          email = @parsed_body[:email]
          password = @parsed_body[:password]
          # For Trusted Delegates signing users in via omniauth
          omni_provider = @parsed_body[:provider]
          omni_uid = @parsed_body[:uid]
          # Allows injecting custom payload data
          custom_data = @parsed_body[:inject] || {}

          found_user = if access
                         Models::User.from_api_key(access, secret)
                       elsif remote_app
                         Models::User.from_identity(omni_provider, omni_uid)
                       elsif email
                         Models::User.from_email(email, password)
                       end

          if found_user
            update_current_user found_user
            Metrics.instance.increment('jwt.tokens.provided')
            { jwt: jwt_token(custom_data: custom_data) }.to_json
          else
            halt 401
          end
        end

        options '/token' do
          halt 200
        end

        # Provide information about the JWTs generated by the server
        get '/meta' do
          {
            algorithm: CONFIG[:jwt][:algorithm],
            issuer: CONFIG[:jwt][:issuer],
            expiration: CONFIG[:jwt][:expiration]
          }.to_json
        end

        options '/meta' do
          halt 200
        end

        # Provide access to the public ECDSA key
        get '/key' do
          {
            data: public_key.export
          }.to_json
        end

        options '/key' do
          halt 200
        end
      end
    end
  end
end
