module ActiveShipping

  class ContractShipmentGroupsResponse < Response
    attr_reader :shipment_groups

    # @params (see ActiveShipping::Response#initialize)
    def initialize(success, message, params = {}, options = {})

      @shipment_groups = Array(options[:shipment_groups])

      super
    end

  end
end
