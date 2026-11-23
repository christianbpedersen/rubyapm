class App < ApplicationRecord
  has_many :hosts, dependent: :delete_all
  has_many :alert_policies, dependent: :destroy
  has_many :incidents, dependent: :delete_all

  after_create { AlertPolicy.defaults_for(self).each(&:save!) }

  validates :name, presence: true, uniqueness: true
  before_validation { self.api_key ||= "nf_#{SecureRandom.hex(16)}" }

  def self.for_ingest(api_key, name)
    app = find_by(api_key: api_key)
    return app if app
    # Development convenience: unknown keys auto-register their app.
    return nil unless Rails.configuration.x.auto_register_apps && api_key.present? && name.present?

    create_with(api_key: api_key).find_or_create_by!(name: name)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_by(api_key: api_key)
  end

  def to_param = "#{id}-#{name.parameterize}"

  # Rollup tables carry app_id without foreign keys (ingest speed), so
  # deleting an app removes their rows explicitly.
  DATA_MODELS = %w[TxRollup AppRollup SegmentRollup SqlRollup SqlStatement ErrorRollup ErrorGroup Trace SlowQuery
                   Deployment RuntimeRollup Incident].freeze

  def destroy_with_data!
    transaction do
      DATA_MODELS.each { |m| m.constantize.where(app_id: id).in_batches(of: 50_000).delete_all }
      destroy!
    end
  end

  def regenerate_api_key!
    update!(api_key: "nf_#{SecureRandom.hex(16)}")
  end
end
