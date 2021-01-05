require 'test_helper'

class LatipayTest < Test::Unit::TestCase
  def setup
    @user_id = 'U007331000'
    @credentials = { user_id: @user_id, wallet_id: 'W007331000', api_key: '7EE1' }
    @order = '22TEST'
    @options = {
      return_url: 'https://kis-next-cms.travellink.com.au?test=latipay',
      ip: '127.0.0.1',
      product_name: 'ticket',
      amount: '0.01',
      payment_method: 'alipay'
    }
    @helper = OffsitePayments::Integrations::Latipay::Helper.new(@order, @credentials, @options)
  end

  def test_purchase_offsite_response
    # Below response from instance running remote test
    response_params = { "token" => @order }
    # require 'pry'
    # binding.pry
    notification = OffsitePayments::Integrations::Latipay::Notification.new(response_params, @credentials)

    secret = OpenSSL::HMAC.hexdigest(OpenSSL::Digest::SHA256.new, @credentials[:api_key], "merchant_reference=#{@order}&user_id=#{@user_id}#{@credentials[:api_key]}")
    assert_equal "https://api.latipay.net/v2/transaction/#{@order}?signature=#{secret}&user_id=#{@user_id}", ActiveUtils::PostsData.last_endpoint

    parsed_response = notification.params
    query = OffsitePayments::Integrations::Latipay::QueryInterface.new(@credentials[:api_key], @credentials[:user_id])
    assert query.validate_response(parsed_response).nil?
    assert_equal 'pending', notification.status

    tampered_params1 = parsed_response.merge('payment_method' => 'foo')
    assert_raise(StandardError) { query.validate_response(tampered_params1) }

    tampered_params2 = parsed_response.merge('currency' => 'USD')
    assert_raise(StandardError) { query.validate_response(tampered_params2) }
  end
end
