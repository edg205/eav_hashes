module ActiveRecord
  module EavHashes
    # Wraps a bunch of EavEntries and lets you use them like you would a hash
    # This class should not be used directly and you should instead let eav_hash_for create one for you
    class EavHash
      # Creates a new EavHash. You should really let eav_hash_for do this for you...
      # @param [ActiveRecord::Base] owner the Model which will own this hash
      # @param [Hash] options the options hash which eav_hash generated
      def initialize(owner, options)
        Util::sanity_check options
        
        @owner = owner
        @options = options
      end

      # Saves any modified entries and deletes any which have been nil'd to save DB space
      def save_entries
        # The entries are lazy-loaded, so don't do anything if they haven't been accessed or modified
        return unless (@entries and @changes_made)

        @entries.values.each do |entry|
          if entry.value.nil?
            entry.delete
          else
            set_entry_owner(entry)
            entry.save
          end
        end
      end

      # Gets the value of an EAV attribute
      # @param [String, Symbol] key
      def [](key)
        raise "Key must be a string or a symbol!" unless key.is_a?(String) or key.is_a?(Symbol)
        load_entries_if_needed
        key = Util.clean_up_key(key)
        return @entries[key].value if @entries[key]
        nil
      end

      # Sets the value of the EAV attribute `key` to `value`
      # @param [String, Symbol] key the attribute
      # @param [Object] value the value
      def []=(key, value)
        update_or_create_entry key, value
      end

      # I don't know why Ruby hashes don't have a shovel operator, but I will make damn sure that I
      # fight the power and stick it to the man by implementing it.
      # @param [Hash, EavHash] dirt the dirt to shovel (ba dum, tss)
      def <<(dirt)
        puts "dirt: #{dirt}"
        validate_keys(dirt) unless dirt.blank?
        if dirt.is_a? Hash
          dirt.each do |key, value|
            update_or_create_entry Util.clean_up_key(key), value
          end
        elsif dirt.is_a? EavHash
          dirt.entries.each do |key, entry|
            update_or_create_entry Util.clean_up_key(key), entry.value
          end
        else
          raise "You can't shovel something that's not a Hash or EavHash here!"
        end

        self
      end

      # Gets the raw hash containing EavEntries by their keys
      def entries
        load_entries_if_needed
      end

      # Gets the actual values this EavHash contains
      def values
        load_entries_if_needed

        ret = []
        @entries.values.each do |value|
          ret << value
        end

        ret
      end

      # Gets the keys this EavHash manages
      def keys
        load_entries_if_needed
        @entries.keys
      end

      # Emulates Hash.each
      def each (&block)
        as_hash.each &block
      end

      # Emulates Hash.each_pair (same as each)
      def each_pair (&block)
        each &block
      end

      # Empties the hash by setting all the values to nil
      # (without committing them, of course)
      def clear
        load_entries_if_needed
        @entries.each do |_, entry|
          entry.value = nil
        end
      end

      # Returns a hash with each entry key mapped to its actual value,
      # not the internal EavEntry
      def as_hash
        load_entries_if_needed
        hsh = {}
        @entries.each do |k, entry|
          hsh[k] = entry.value
        end

        hsh
      end

      # Take the crap out of #inspect calls
      def inspect
        as_hash
      end

    private
      def update_or_create_entry(key, value)
        raise "Key must be a string or a symbol!" unless key.is_a?(String) or key.is_a?(Symbol)
        
        key = @options[:key_class].find_by(key_name: key)
        
        load_entries_if_needed

        @changes_made = true
        @owner.updated_at = Time.now

        if @entries[key]
          @entries[key].value = value
        else
          new_entry = @options[:entry_class].new
          set_entry_owner(new_entry)
          new_entry.key = key.key_name
          new_entry.symbol_key = key.key_name.is_a?(Symbol)
          new_entry.value = value
          new_entry.send("#{@options[:key_assoc_name]}_id=".to_sym, key.id)
          @entries[key] = new_entry
          
          value
        end
      end

      # Since entries are lazy-loaded, this is called just before an operation on an entry happens and
      # loads the rows only once per EavHash lifetime.
      def load_entries_if_needed
        if @entries.nil?
          @entries = {}
          rows_from_model = @owner.send("#{@options[:entry_assoc_name]}")
          rows_from_model.each do |row|
            @entries[row.send(@options[:key_assoc_name]).key_name] = row
          end
        end
        
        @entries
      end
      
      def validate_keys(data)
        if data.is_a? Hash
          data = data.inject({}){|memo,(k,v)| memo[Util.clean_up_key(k)] = v; memo}
        elsif data.is_a? EavHash
          puts "EavHash: data: #{data.inspect}"
        end

        provided_keys = data.keys
        
        existing_keys = @options[:key_class].pluck(:key_name,:id)
        existing_key_names = existing_keys.map {|x| x[0].to_sym}
        
        missing_keys = (provided_keys - existing_key_names)
        raise "Keys must already have been defined. Missing Keys: #{missing_keys}" unless missing_keys.empty? 
        
        data
      end

      # Sets an entry's owner ID. This is called when we save attributes for a model which has just been
      # created and not committed to the DB prior to having its EAV hash(es) modified
      # @param [EavEntry] entry the entry whose owner to change
      def set_entry_owner(entry)
        entry.send "#{@options[:parent_assoc_name]}_id=", @owner.id
      end
    end
  end
end
