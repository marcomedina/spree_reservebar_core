Spree::Order.class_eval do
	attr_accessible :is_legal_age, :is_gift, :gift_attributes
	attr_accessor :is_gift
	
	attr_accessible :has_accepted_terms
	attr_accessor :has_accepted_terms

	has_and_belongs_to_many :retailers, :join_table => :spree_orders_retailers
	belongs_to :gift
	
	accepts_nested_attributes_for :gift

  scope :non_accepted_hours,
    lambda {|n|
      where(["spree_orders.accepted_at is ? and spree_orders.updated_at < ? and spree_orders.state = ?", nil, Time.now - n.hours, "complete"])
    }
  
  search_methods :non_accepted_hours
	
	# Scope to find all orders that have not been accepted by retailers in a given time frame
	scope :not_accepted_hours,
    lambda {|number_of_hours|
      where(["spree_orders.accepted_at is ? and spree_orders.updated_at < ? and spree_orders.state = ?", nil, Time.now - number_of_hours.hours, "complete"])
    }
	
	search_methods :not_accepted_hours
  
	state_machine :initial => :cart, :use_transactions => false do
		before_transition :to => 'delivery', :do => :validate_legal_drinking_age?
				
		# add the gift notification after order.finalize!
		# note that this adds a new callback to the chain, it does not overreid the existing callbacks
		# we had called order.finalize! here, which was then executed twice....
		after_transition :to => 'complete' do |order, transition|
			order.gift_notification if order.is_gift?
			Spree::OrderMailer.retailer_submitted_email(order).deliver if order.retailer
		end
		
	end
	
	# Pseudo states that embedd special logic for reservebar.com
	# uses packed_at column to allow the retailer to indicate that he pas packed the item and it is ready for pick up 
	# we'll do state transition such that retailer hits 'ready for pick up' , which changes packed_at, and then fede scanning changes to shipped
	def extended_state
	  if self.state == 'complete'
  	  if !self.accepted_at
  	    'submitted'
      elsif self.accepted_at && (self.packed_at == nil) && self.shipment_state != 'shipped'
        'accepted'
      elsif self.packed_at && self.shipment_state != 'shipped'
        'ready_for_pick_up'
      elsif self.shipped?
        'shipped'
      end
    else
      self.state
    end
  end
  
	
	# Override the address used for calculating taxes.
	# Reservebar.com uses the retailer's physial address, rather then the ship_address to determine taxes
	# Returns the relevant zone (if any) to be used for taxation purposes.  Uses default tax zone
  # unless there is a specific match
  def tax_zone
    if Spree::Config[:tax_using_retailer_address]
      if retailer
        zone_address = retailer.physical_address
      else
        zone_address = nil
      end
    else
      zone_address = Spree::Config[:tax_using_ship_address] ? ship_address : bill_address
    end
    Spree::Zone.match(zone_address) || Spree::Zone.default_tax
  end
  
	
  def gift_notification
    Spree::OrderMailer.giftee_notify_email(self).deliver
  end
	
	def retailer
	  self.retailers.last
  end
  
  def retailer=(retailer)
    self.retailers = []
    self.retailers << retailer
  end
  
	def retailer_id
		retailer.id if retailer
	end
	
	def validate_legal_drinking_age?
		is_legal_age
	end
	

	def is_gift
		is_gift? ? true : false
	end
	
	def is_gift?
		gift.present?
	end
	
	# get all shipping categories for an order, used to find a retailer that can fulfil this order.
	def shipping_categories
	  self.line_items.collect {|l| l.product.shipping_category_id}.uniq
  end
  
  # returns true, if the order only has products in the wine category
  def has_only_wine?
    self.shipping_categories.count == 1 && 
    self.shipping_categories.first == Spree::ShippingCategory.find_by_name('Wine')
  end
  
  
  # Calculates the total amount due to the retailer based on current settings
  # Note that the gift packaging cost does not go to the retailer, but all sales tax does
  def total_amount_due_to_retailer
    shipping = self.retailer.reimburse_shipping_cost ? self.ship_total : 0.0
    product_cost = (self.line_items.collect {|line_item| line_item.variant.product_costs.where(:retailer_id => self.retailer_id).first.cost_price * line_item.quantity }).sum
    self.tax_total + shipping + product_cost
  end
  
  
  # Returns the number of bottles in the order, so we can limit 
  # Cache counts?
  def number_of_bottles
    bottles = self.line_items.inject(0) {|bottles, line_item| bottles + line_item.quantity}
  end
  
  
  
end
