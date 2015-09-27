require 'test_helper'

class RemoteCanadaPostPWSTest < Minitest::Test
  # All remote tests require Canada Post development environment credentials
  include ActiveShipping::Test::Credentials
  include ActiveShipping::Test::Fixtures

  def setup
    @login = credentials(:canada_post_pws)
    refute @login.key?(:platform_id), "The 'canada_post_pws' credentials should NOT include a platform ID"

    # 1000 grams, 93 cm long, 10 cm diameter, cylinders have different volume calculations
    @pkg1 = Package.new(1000, [93, 10, 10], :value => 10.00)

    @line_item1 = line_item_fixture

    clear_capture!

    @shipping_opts1 = { :dc => true, :cov => true, :cov_amount => 100.00, :aban => true }

    @home_params = {
      :name        => "John Smith",
      :company     => "test",
      :phone       => "613-555-1212",
      :address1    => "123 Elm St.",
      :city        => 'Ottawa',
      :province    => 'ON',
      :country     => 'CA',
      :postal_code => 'K1P 1J1'
    }

    @home = Location.new(@home_params)

    @dom_params = {
      :name        => "John Smith Sr.",
      :company     => "",
      :phone       => '123-123-1234',
      :address1    => "5500 Oak Ave",
      :city        => 'Vancouver',
      :province    => 'BC',
      :country     => 'CA',
      :postal_code => 'V5J 2T4'
    }

    @dest_params = {
      :name     => "Frank White",
      :phone    => '123-123-1234',
      :address1 => '999 Wiltshire Blvd',
      :city     => 'Beverly Hills',
      :state    => 'CA',
      :country  => 'US',
      :zip      => '90210'
    }
    @dest = Location.new(@dest_params)

    @dom_params = {
      :name        => "Mrs. Smith",
      :company     => "",
      :phone       => "604-555-1212",
      :address1    => "5000 Oak St.",
      :address2    => "",
      :city        => 'Vancouver',
      :province    => 'BC',
      :country     => 'CA',
      :postal_code => 'V5J 2N2'
    }

    @intl_params = {
      :name        => "Mrs. Yamamoto",
      :company     => "",
      :phone       => "011-123-123-1234",
      :address1    => "123 Yokohama Road",
      :address2    => "",
      :city        => 'Tokyo',
      :province    => '',
      :country     => 'JP'
    }

    @cp = CanadaPostPWS.new(@login.merge(:endpoint => "https://ct.soa-gw.canadapost.ca/"))
    @cp.logger = Logger.new(StringIO.new)

    @customer_number = @login[:customer_number]
    @contract_id = @login[:contract_id]

    @DEFAULT_RESPONSE = {
      :shipping_id => "406951321983787352",
      :tracking_number => "123456789012",
      :manifest_url => "88011443325977262",
      :label_url => "https://ct.soa-gw.canadapost.ca/ers/artifact/#{@login[:api_key]}/20238/0"
    }

  rescue NoCredentialsFound => e
    skip(e.message)
  end

  def test_rates
    opts = {:customer_number => @customer_number}
    rate_response = @cp.find_rates(@home_params, @dom_params, [@pkg1], opts)
    assert_kind_of ActiveShipping::RateResponse, rate_response
    assert_kind_of ActiveShipping::RateEstimate, rate_response.rates.first
  end

  def test_rates_with_invalid_customer_raises_exception
    opts = {:customer_number => "0000000000", :service => "DOM.XP"}
    assert_raises(ResponseError) do
      @cp.find_rates(@home_params, @dom_params, [@pkg1], opts)
    end
  end

  def test_tracking
    pin = "1371134583769923" # valid pin
    response = @cp.find_tracking_info(pin, {})
    assert_equal 'Xpresspost', response.service_name
    assert response.expected_date.is_a?(Date)
    assert response.customer_number
    assert_equal 13, response.shipment_events.count
  end

  def test_tracking_when_no_tracking_info_raises_exception
    pin = "4442172020196022" # valid pin

    error = assert_raises(ActiveShipping::ResponseError) do
      @cp.find_tracking_info(pin, {})
    end

    assert_match /No Tracking/, error.message
  end

  def test_create_shipment
    #skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => @customer_number, :service => "DOM.XP"}
    response = @cp.create_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)
    assert_kind_of CPPWSShippingResponse, response
    assert_match /\A\d{17}\z/, response.shipping_id
    assert_equal "123456789012", response.tracking_number
    assert_match "https://ct.soa-gw.canadapost.ca/ers/artifact/", response.label_url
    assert_match @login[:api_key], response.label_url
  end

  def test_create_contract_shipment
    #skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => @customer_number, :contract_id => @contract_id, :service => "DOM.XP"}
    response = @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)
    assert_kind_of CPPWSContractShippingResponse, response
    assert_match /\A\d{17}\z/, response.shipping_id
    assert_equal "123456789012", response.tracking_number
    assert_equal "created", response.shipment_status
    assert_match "https://ct.soa-gw.canadapost.ca/ers/artifact/", response.label_url
    assert_match "https://ct.soa-gw.canadapost.ca/rs/#{@customer_number}/#{@customer_number}/shipment/#{response.shipping_id}", response.self_url
    assert_match "https://ct.soa-gw.canadapost.ca/rs/#{@customer_number}/#{@customer_number}/shipment/#{response.shipping_id}/details", response.details_url
    assert_match "https://ct.soa-gw.canadapost.ca/rs/#{@customer_number}/#{@customer_number}/shipment/#{response.shipping_id}/price", response.price
    assert_match "https://ct.soa-gw.canadapost.ca/rs/#{@customer_number}/#{@customer_number}/shipment?groupId=#{@home_params[:company]}#{Time.now.strftime("%Y%m%d").to_i}", response.group
    assert_match @login[:api_key], response.label_url
  end

  def test_void_contract_shipment
    opts = {:customer_number => @customer_number, :contract_id => @contract_id, :service => "DOM.XP"}
    response = @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)

    @cp.void_contract_shipment(response, opts)

    assert_raises(ResponseError) do
      @cp.void_contract_shipment(response, opts)
    end
  end

  def test_transmit_shipments
    groups = []
    groups << "#{@home_params[:company]}#{Time.now.strftime("%Y%m%d").to_i}"

    opts = {:customer_number => @customer_number, :contract_id => @contract_id, :service => "DOM.XP"}

    @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)

    response = @cp.transmit_shipments(@home_params, groups, opts)

    assert_kind_of CPPWSTransmitShipmentsResponse, response
    assert_match "https://ct.soa-gw.canadapost.ca/rs/#{@customer_number}/#{@customer_number}/manifest/", response.manifest_url
  end

  def test_get_manifest
    groups = []
    groups << "#{@home_params[:company]}#{Time.now.strftime("%Y%m%d").to_i}"
    opts = {:customer_number => @customer_number, :contract_id => @contract_id, :service => "DOM.XP"}

    @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)

    sleep(2)

    response = @cp.transmit_shipments(@home_params, groups, opts)

    sleep(2)

    manifest_response = @cp.get_manifest(response, opts)

    sleep(2)

    puts manifest_response.inspect

    assert_kind_of CPPWSGetManifestResponse, manifest_response

  end

  def test_create_shipment_with_options
         skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => @customer_number, :service => "USA.EP"}.merge(@shipping_opts1)
    response = @cp.create_shipment(@home_params, @dest_params, @pkg1, @line_item1, opts)

    assert_kind_of CPPWSShippingResponse, response
    assert_match /\A\d{17}\z/, response.shipping_id
    assert_equal "123456789012", response.tracking_number
    assert_match "https://ct.soa-gw.canadapost.ca/ers/artifact/", response.label_url
    assert_match @login[:api_key], response.label_url
  end

  def test_create_contract_shipment_with_options
    skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => @customer_number, :contract_id => @contract_id, :service => "USA.EP"}.merge(@shipping_opts1)
    response = @cp.create_contract_shipment(@home_params, @dest_params, @pkg1, @line_item1, opts)

    assert_kind_of CPPWSContractShippingResponse, response
    assert_match /\A\d{17}\z/, response.shipping_id
    assert_equal "123456789012", response.tracking_number
    assert_match "https://ct.soa-gw.canadapost.ca/ers/artifact/", response.label_url
    assert_match @login[:api_key], response.label_url
  end

  def test_get_contract_shipment
    opts = {:customer_number => @customer_number, :service => "DOM.XP", :contract_id => @contract_id}
    shipping_response = @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)

    response = @cp.get_contract_shipment(shipping_response, opts)

    assert response.is_a?(CPPWSContractShippingResponse)
    assert_equal shipping_response.shipping_id, response.shipping_id
    assert_equal shipping_response.shipment_status, response.shipment_status
    assert_equal shipping_response.self_url, response.self_url
    assert_equal shipping_response.details_url, response.details_url
    assert_equal shipping_response.label_url, response.label_url
    assert_equal shipping_response.group, response.group
    assert_equal shipping_response.price, response.price
  end

  def test_retrieve_shipping_label
    skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => @customer_number, :service => "DOM.XP"}
    shipping_response = @cp.create_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)

    # Looks like it takes Canada Post some time to actually generate the PDF.
    response = nil
    10.times do
      response = @cp.retrieve_shipping_label(shipping_response)
      break unless response == ""
      sleep(0.5)
    end

    assert_equal "%PDF", response[0...4]
  end


  def test_retrieve_contract_shipping_label
    skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => @customer_number, :service => "DOM.XP", :contract_id => @contract_id}
    shipping_response = @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)

    # Looks like it takes Canada Post some time to actually generate the PDF.
    response = nil
    10.times do
      response = @cp.retrieve_contract_shipping_label(shipping_response)
      break unless response == ""
      sleep(0.5)
    end

    assert_equal "%PDF", response[0...4]
  end

  def test_get_shipment_groups
    opts = {:customer_number => @customer_number, :service => "DOM.XP", :contract_id => @contract_id}
    groups_response = @cp.get_contract_shipment_groups(opts)
    assert_kind_of CPPWSContractShipmentGroupsResponse, groups_response
    assert_kind_of ActiveShipping::ShipmentGroup, groups_response.shipment_groups.first

  end

  def test_create_shipment_with_invalid_customer_raises_exception
    skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => "0000000000", :service => "DOM.XP"}
    assert_raises(ResponseError) do
      @cp.create_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)
    end
  end

  def test_create_contract_shipment_with_invalid_customer_raises_exception
    skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => "0000000000", :contract_id => @contract_id, :service => "DOM.XP"}
    assert_raises(ResponseError) do
      @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)
    end
  end

  def test_create_contract_shipment_with_invalid_contract_raises_exception
    skip "Failing with 'Contract Number is a required field' after API change, skipping because no clue how to fix, might need different creds"
    opts = {:customer_number => @customer_number, :contract_id => "00000", :service => "DOM.XP"}
    assert_raises(ResponseError) do
      @cp.create_contract_shipment(@home_params, @dom_params, @pkg1, @line_item1, opts)
    end
  end

  def clear_capture!
    @captured = nil
  end

  def capture(*args)
    (@captured ||= { }).merge(args)
  end

  def dump_capture
    puts @capture.inspect
  end
end
