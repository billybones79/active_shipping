module ActiveShipping
  class ShipmentGroup
    attr_reader :link, :group_id

    def initialize(link, group_id)
      @link, @group_id = link, group_id
    end

  end
end
