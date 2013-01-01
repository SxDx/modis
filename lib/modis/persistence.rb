module Modis
  module Persistence
    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def key_namespace
        return @key_namespace if @key_namespace
        parts = name.split('::').map(&:underscore)
        parts.unshift(Modis.config.key_namespace)
        @key_namespace = parts.compact.join(':')
      end

      def key_for(id)
        "#{key_namespace}:#{id}"
      end

      def create(attrs)
        # run_callbacks :create do
          model = instantiate(attrs)
          model.save
          model
        # end
      end

      def create!(attrs)
        # run_callbacks :create do
        model = instantiate(attrs)
        model.save!
        model
        # end
      end
    end

    def key_namespace
      self.class.key_namespace
    end

    def persisted?
      true
    end

    def key
      new_record? ? nil : self.class.key_for(id)
    end

    def new_record?
      defined?(@new_record) ? @new_record : true
    end

    def save
      future = nil
      set_id if new_record?

      self.class.transaction do
        callback = new_record? ? :update : :create
        run_callbacks callback do
          future = Redis.current.hmset(self.class.key_for(id), *attributes.to_a.flatten)
          track(id) if new_record?
        end
      end

      if future && future.value == 'OK'
        reset_changes
        @new_record = false
        true
      else
        false
      end
    end

    def save!
      raise RecordNotSaved unless save
    end

    def destroy
      self.class.transaction do
        run_callbacks :destroy do
          Redis.current.del(key)
          untrack(id)
        end
      end
    end

    protected

    def set_id
      self.id = Redis.current.incr("#{key_namespace}_id_seq")
    end

    def track(id)
      Redis.current.sadd(self.class.key_for(:all), id)
    end

    def untrack(id)
      Redis.current.srem(self.class.key_for(:all), id)
    end
  end
end
