module OffsitePayments
  module Integrations
    module Latipay

      def self.notification(post, options = {})
        Notification.new(post, options)
      end

      def self.return(query_string, options = {})
        Return.new(query_string, options)
      end

      class Interface
        include ActiveUtils::PostsData # ssl_get/post

        def self.base_url
          "https://api.latipay.net/v2"
        end

        def initialize(api_key)
          @api_key = api_key
        end

        def sign(fields)
          message = fields.compact.sort.map{ |k,v| "#{k.to_s}=#{v}" }.join('&').concat(@api_key)
          OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, @api_key, message)
        end
  
        def verify_signature(message, signature)
          signature == OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, @api_key, message)
        end

        private

        def standard_headers
          {
            'Content-Type' => 'application/json'
          }
        end

        def parse_response(raw_response)
          JSON.parse(raw_response)
        end

        class RequestError < StandardError
          attr_reader :exception, :message, :response_code

          def initialize(response)
            @response      = response
            @response_code = @response['code']
            @success       = @response_code == '0'
            @message       = @response['message']
          end

          ERRORS = {
            '201' => 'order not exist',
            '204' => 'Some fields from input are null',
            '205' => 'Cannot find out corresponding key for the user code or user is disabled or user is not activity',
            '206' => 'Signature from Merchant request is wrong',
            '207' => 'Param is wrong',
            '300' => 'Gateway not exist',
            '301' => 'Wrong account info or currency info',
            '302' => 'Paycompany not exist',
            '303' => 'Wrong pay type from merchant',
            '304' => 'Wallet does not support this payment method',
            '305' => 'No margin plan for the merchant',
            '450' => 'Wallet not assign to user',
            '1'   => 'FAIL'
          }

          def success?
            !!@success
          end

          def errors
            fail NotImplementedError, "This method must be implemented on the subclass"
          end

          def error_code_text
            errors[@response_code]
          end
        end
      end

      class TransactionInterface < Interface
        def self.url
          "#{base_url}/transaction"
        end

        def call(options)
          options[:signature] = self.sign(options)
          puts '--------'
          puts options.to_json
          raw_response = ssl_post(self.class.url, options.to_json, standard_headers)
          parsed_response = parse_response(raw_response)
          puts '--------'
          puts parsed_response
          validate_response(parsed_response)
          "#{parsed_response['host_url']}/#{parsed_response['nonce']}"
        end

        def validate_response(parsed_response)
          raise TransactionRequestError, parsed_response unless parsed_response['code'] == 0
          message = parsed_response['nonce'] + parsed_response['host_url']
          signature = parsed_response['signature']
          raise StandardError, 'Invalid Signature in response' unless verify_signature(message, signature)
        end

        class TransactionRequestError < RequestError
          def errors
            ERRORS
          end
        end
      end

      class RefundInterface < Interface
        def self.url
          "https://api.latipay.net/refund"
        end

        def call(options)
          options[:signature] = self.sign(options)
          puts '--------'
          puts options.to_json
          raw_response = ssl_post(self.class.url, options.to_json, standard_headers)
          parsed_response = parse_response(raw_response)
          puts '--------'
          puts parsed_response
          validate_response(parsed_response)
          "#{parsed_response['host_url']}/#{parsed_response['nonce']}"
        end

        def validate_response(parsed_response)
          raise TransactionRequestError, parsed_response unless parsed_response['code'] == 0
          message = parsed_response['nonce'] + parsed_response['host_url']
          signature = parsed_response['signature']
          raise StandardError, 'Invalid Signature in response' unless verify_signature(message, signature)
        end

        class RefundInterface < RequestError
          def errors
            ERRORS
          end
        end
      end

      class Helper < OffsitePayments::Helper
        def initialize(order, credentials, options = {})
          @api_key = credentials.fetch(:api_key)
          super(order, credentials.fetch(:user_id), options.except(
            :payment_method, :ip, :product_name
          ))

          add_field 'version', '2.0'
          add_field 'payment_method', options.fetch(:payment_method)
          add_field 'ip', options.fetch(:ip)
          add_field 'product_name', options.fetch(:product_name)
          add_field 'callback_url', options.fetch(:callback_url) { options.fetch(:return_url) }
          add_field 'wallet_id', credentials.fetch(:wallet_id)
          add_field 'amount', options.fetch(:amount)
          add_field 'return_url', options.fetch(:return_url)
        end

        mapping :order, 'merchant_reference'
        mapping :account, 'user_id'


        def transaction_url
          if form_fields['payment_method'] == 'wechat'
            form_fields.merge!({ 'present_qr' => '1' })
          end
          TransactionInterface.new(@api_key).call(form_fields)
        end
      end

      class Notification < OffsitePayments::Notification
        def complete?
          params['']
        end

        def item_id
          params['']
        end

        def transaction_id
          params['']
        end

        # When was this payment received by the client.
        def received_at
          params['']
        end

        def payer_email
          params['']
        end

        def receiver_email
          params['']
        end

        def security_key
          params['']
        end

        # the money amount we received in X.2 decimal.
        def gross
          params['']
        end

        # Was this a test transaction?
        def test?
          params[''] == 'test'
        end

        def status
          params['']
        end

        # Acknowledge the transaction to Latipay. This method has to be called after a new
        # apc arrives. Latipay will verify that all the information we received are correct and will return a
        # ok or a fail.
        #
        # Example:
        #
        #   def ipn
        #     notify = LatipayNotification.new(request.raw_post)
        #
        #     if notify.acknowledge
        #       ... process order ... if notify.complete?
        #     else
        #       ... log possible hacking attempt ...
        #     end
        def acknowledge(authcode = nil)
          payload = raw

          uri = URI.parse(Latipay.notification_confirmation_url)

          request = Net::HTTP::Post.new(uri.path)

          request['Content-Length'] = "#{payload.size}"
          request['User-Agent'] = "Active Merchant -- http://activemerchant.org/"
          request['Content-Type'] = "application/x-www-form-urlencoded"

          http = Net::HTTP.new(uri.host, uri.port)
          http.verify_mode    = OpenSSL::SSL::VERIFY_NONE unless @ssl_strict
          http.use_ssl        = true

          response = http.request(request, payload)

          # Replace with the appropriate codes
          raise StandardError.new("Faulty Latipay result: #{response.body}") unless ["AUTHORISED", "DECLINED"].include?(response.body)
          response.body == "AUTHORISED"
        end

        private

        # Take the posted data and move the relevant data into a hash
        def parse(post)
          @raw = post.to_s
          for line in @raw.split('&')
            key, value = *line.scan( %r{^([A-Za-z0-9_.-]+)\=(.*)$} ).flatten
            params[key] = CGI.unescape(value.to_s) if key.present?
          end
        end
      end
    end
  end
end
