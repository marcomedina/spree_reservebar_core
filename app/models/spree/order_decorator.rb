Spree::Order.class_eval do
	attr_accessible :is_legal_age, :is_gift, :gift_attributes
	attr_accessor :is_gift

	has_and_belongs_to_many :retailers, :join_table => :spree_orders_retailers
	belongs_to :gift
	
	accepts_nested_attributes_for :gift
	
	state_machine :initial => :cart, :use_transactions => false do
		before_transition :to => 'delivery', :do => :validate_legal_drinking_age?
		
		after_transition :to => 'complete' do |order, transition|
			order.finalize!
			order.gift_notification if order.is_gift?
		end
		
	end
	
  def gift_notification
    Spree::OrderMailer.gift_notify_email(self).deliver
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
	
	# get all shipping categories for an order
	# this is based on what
	def shipping_categories
	  self.line_items.collect {|l| l.product.shipping_category_id}.uniq
  end
  
  # returns true, if the order only has products in the wine category
  def has_only_wine?
    self.shipping_categories.count == 1 && 
    self.shipping_categories.first == Spree::ShippingCategory.find_by_name('Wine')
  end
end
