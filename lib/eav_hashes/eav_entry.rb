module ActiveRecord
  module EavHashes
    # Used instead of nil when a nil value is assigned
    # (otherwise, the value will try to deserialize itself and
    #  that would break everything horrifically)
    class NilPlaceholder; end

    # Represent an EAV row. This class should NOT be used directly, instead it should be inherited from
    # by the class generated by eav_hash_for.
    class EavEntry < ActiveRecord::Base
      # prevent activerecord from thinking we're trying to do STI
      self.abstract_class = true

      # Tell ActiveRecord to convert the value to its DB storable format
      before_save :serialize_value

      # Contains the values the value_type column should have based on the type of the value being stored
      SUPPORTED_TYPES = {
          :String     => 0,
          :Symbol     => 1,
          :Integer    => 2,
          :Fixnum     => 2,
          :Bignum     => 2,
          :Float      => 3,
          :Complex    => 4,
          :Rational   => 5,
          :Boolean    => 6, # For code readability
          :TrueClass  => 6,
          :FalseClass => 6,
          :Object     => 7 # anything else (including Hashes, Arrays) will be serialized to yaml and saved as Object
      }

      # Does some sanity checks.
      def after_initialize
        raise "key should be a string or symbol!" unless key.is_a? String or key.is_a? Symbol
        raise "value should not be empty!" if @value.is_a? String and value.empty?
        raise "value should not be nil!" if @value.nil?
      end

      # Gets the EAV row's value
      def value
        return nil if @value.is_a? NilPlaceholder
        @value.nil? ? deserialize_value : @value
      end

      # Sets the EAV row's value
      # @param [Object] val the value
      def value= (val)
        @value = (val.nil? ? 'None' : val)
      end

      # Gets the value_type column's value for the type of value passed
      # @param [Object] val the object whose value_type to determine
      def self.get_value_type (val)
        return nil if val.nil?
        ret = SUPPORTED_TYPES[val.class.name.to_sym]
        if ret.nil?
          ret = SUPPORTED_TYPES[:Object]
        end
        ret
      end

    private
      # Sets the value_type column to the appropriate value based on the value's type
      def update_value_type
        write_attribute :value_type, EavEntry.get_value_type(@value)
      end

      # Converts the value to its database-storable form and tells ActiveRecord that it's been changed (if it has)
      def serialize_value
        # Returning nil will prevent the row from being saved, to save some time since the EavHash that manages this
        # entry will have marked it for deletion.
        raise "Tried to save with a nil value!" if @value.nil? or @value.is_a? NilPlaceholder

        update_value_type
        if value_type == SUPPORTED_TYPES[:Object]
          write_attribute :value, YAML::dump(@value)
        else
          write_attribute :value, @value.to_s
        end

        read_attribute :value
      end

      # Converts the value from it's database representation to the type specified in the value_type column.
      def deserialize_value
        if @value.nil?
          @value = read_attribute :value
        end

        case value_type
          when SUPPORTED_TYPES[:Object] # or Hash, Array, etc.
            @value = YAML::load @value
          when SUPPORTED_TYPES[:Symbol]
            @value = @value.to_sym
          when SUPPORTED_TYPES[:Integer] # or Fixnum, Bignum
            @value = @value.to_i
          when SUPPORTED_TYPES[:Float]
            @value = @value.to_f
          when SUPPORTED_TYPES[:Complex]
            @value = Complex @value
          when SUPPORTED_TYPES[:Rational]
            @value = Rational @value
          when SUPPORTED_TYPES[:Boolean]
            @value = (@value == "true")
          else
            @value
        end
      end
    end
  end
end
