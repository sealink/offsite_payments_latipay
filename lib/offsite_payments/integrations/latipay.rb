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

        def initialize(api_key, user_id)
          @api_key = api_key
          @user_id = user_id
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

          # Latipay doesn't provide error codes for each interface, this is the only list for all the errors.
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
          raw_response = ssl_post(self.class.url, options.to_json, standard_headers)
          parsed_response = parse_response(raw_response)
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

      class QueryInterface < Interface
        def self.url(merchant_reference)
          "#{base_url}/transaction/#{CGI.escape(merchant_reference)}"
        end

        def call(merchant_reference)
          options = { user_id: @user_id }
          signature = self.sign(options.merge({ merchant_reference: merchant_reference }))
          options[:signature] = signature

          raise ArgumentError, "Merchant reference must be specified" if merchant_reference.blank?
          url = "#{self.class.url(merchant_reference)}?#{options.to_query}"
          raw_response = ssl_get(url, standard_headers)
          parsed_response = parse_response(raw_response)
          validate_response(parsed_response)
          parsed_response
        end

        def validate_response(parsed_response)
          raise QueryRequestError, parsed_response unless parsed_response['code'] == 0
          message = "#{parsed_response['merchant_reference']}#{parsed_response['payment_method']}#{parsed_response['status']}#{parsed_response['currency']}#{parsed_response['amount']}"
          signature = parsed_response['signature']
          raise StandardError, 'Invalid Signature in response' unless verify_signature(message, signature)
        end

        class QueryRequestError < RequestError
          def errors
            ERRORS
          end
        end
      end

      class RefundInterface < Interface
        def self.url
          # according to latipay doc, this url does not have a version part.
          "https://api.latipay.net/refund"
        end

        def call(order_id, refund_amount, reference = '')
          raise ArgumentError, "Order ID must be specified" if order_id.blank?
          raise ArgumentError, "Refund amount must be specified" if refund_amount.blank?
          options = { refund_amount: refund_amount, reference: reference, user_id: @user_id, order_id: order_id }
          options[:signature] = self.sign(options)
          raw_response = ssl_post(self.class.url, options.to_json, standard_headers)
          parsed_response = parse_response(raw_response)
          validate_response(parsed_response)
          parsed_response['message']
        end

        def validate_response(parsed_response)
          raise RefundRequestError, parsed_response unless parsed_response['code'] == 0
        end

        class RefundRequestError < RequestError
          def errors
            ERRORS
          end
        end
      end

      class Helper < OffsitePayments::Helper
        def initialize(order, credentials, options = {})
          @api_key = credentials.fetch(:api_key)
          @user_id = credentials.fetch(:user_id)
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
          TransactionInterface.new(@api_key, @user_id).call(form_fields)
        end
      end

      class Notification < OffsitePayments::Notification
        def initialize(params, credentials = {})
          token = params.fetch('Token') { params.fetch('token') }
          @params = QueryInterface.new(credentials.fetch(:api_key), credentials.fetch(:user_id)).call(token)
        end

        def complete?
          params['status'] == 'paid'
        end

        def transaction_id
          params['order_id']
        end

        # the money amount we received in X.2 decimal.
        def gross
          params['amount']
        end

        def status
          params['status']
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
          true
        end
      end
    end
  end
end
