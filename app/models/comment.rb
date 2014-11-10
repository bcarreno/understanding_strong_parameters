class Comment < ActiveRecord::Base
  belongs_to :article
  accepts_nested_attributes_for :article
end
