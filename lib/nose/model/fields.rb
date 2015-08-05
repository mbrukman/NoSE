require 'date'
require 'faker'
require 'forwardable'
require 'zlib'

module NoSE
  # Fields attached to each entity in the entity graph model
  module Fields
    # A single field on an {Entity}
    class Field
      include Supertype

      attr_reader :name, :size, :parent, :key
      attr_accessor :primary_key
      alias_method :primary_key?, :primary_key

      # The Ruby type of values stored in this field
      TYPE = nil

      def initialize(name, size, count: nil)
        @name = name
        @size = size
        @cardinality = count
        @primary_key = false
      end

      # Compare by parent entity and name
      def ==(other)
        match = other.is_a?(Field) && @parent == other.parent &&
                @name == other.name
        other_key = other.instance_variable_get(:@key)
        match && (@key.nil? || @other_key.nil? || @key == other_key)
      end
      alias_method :eql?, :==

      # Hash by entity and name
      # @return [Fixnum]
      def hash
        @hash ||= Zlib.crc32 [@parent.name, @name, @key && @key.name].to_s
      end

      # :nocov:
      def to_color
        "[blue]#{@parent.name}[/].[blue]#{@name}[/]"
      end
      # :nocov:

      # A simple string representing the field
      def id
        # If the key is not set, we can't get an ID
        fail if @key.nil?

        id = @parent.name
        id += "_#{@key.name}" unless @key.is_a?(Fields::IDField)
        id + "_#{@name}"
      end

      # Set the estimated cardinality of the field
      # @return [Field]
      def *(other)
        @cardinality = other
        self
      end

      # Return the previously set cardinality, falling back to the number of
      # entities for the field if set, or just 1
      def cardinality
        @cardinality || @parent.count || 1
      end

      # @abstract Subclasses should produce a typed value from a string
      # :nocov:
      def self.value_from_string(_string)
        fail NotImplementedError
      end
      # :nocov:

      # @abstract Subclasses should produce a random value of the correct type
      # :nocov:
      def random_value
        fail NotImplementedError
      end
      # :nocov:

      # Create a copy of this field, but attached to a particular key
      def with_key(key)
        keyed_field = dup
        keyed_field.instance_variable_set(:@key, key)
        keyed_field.freeze
      end

      # Attach the key to the identity of the parent
      def with_identity_key
        with_key @parent.id_fields.first
      end

      # Populate a helper DSL object with all subclasses of Field
      def self.inherited(child_class)
        # We use separate methods for foreign keys
        begin
          fk_class = Fields.const_get('ForeignKeyField')
        rescue NameError
          fk_class = nil
        end
        return if !fk_class.nil? && child_class <= fk_class

        # Add convenience methods for all field types for an entity DSL
        method_regex = /^NoSE::Fields::(.*?)(Field)?$/
        method_name = child_class.name.sub(method_regex, '\1')
        EntityDSL.send :define_method, method_name,
                       (proc do |*args|
                         send(:instance_variable_get, :@entity).send \
                           :<<, child_class.new(*args)
                       end)

        child_class.send(:include, Subtype)
      end
      private_class_method :inherited
    end

    # Field holding an integer
    class IntegerField < Field
      # Integers are stored as integers
      TYPE = Integer

      def initialize(name, **options)
        super(name, 8, **options)
      end

      # Parse an Integer from the provided parameter
      def self.value_from_string(string)
        string.to_i
      end

      # Random numbers up to the given size
      def random_value
        rand(@cardinality)
      end
    end

    # Field holding a float
    class FloatField < Field
      # Any Fixnum is a valid float
      TYPE = Fixnum

      def initialize(name, **options)
        super(name, 8, **options)
      end

      # Parse a Float from the provided parameter
      def self.value_from_string(string)
        string.to_f
      end

      # Random numbers up to the given size
      def random_value
        rand(@cardinality).to_f
      end
    end

    # Field holding a string of some average length
    class StringField < Field
      # Strings are stored as strings
      TYPE = String

      def initialize(name, length = 10, **options)
        super(name, length, **options)
      end

      # Return the String parameter as-is
      def self.value_from_string(string)
        string
      end

      # A random string of the correct length
      def random_value
        Faker::Lorem.characters(@size)
      end
    end

    # Field holding a date
    class DateField < Field
      # Time is used to store timestamps
      TYPE = Time

      def initialize(name, **options)
        super(name, 8, **options)
      end

      # Parse a DateTime from the provided parameter
      def self.value_from_string(string)
        begin
          DateTime.parse(string).to_time
        rescue ArgumentError
          fail TypeError
        end
      end

      # A random date within 2 years surrounding today
      def random_value
        Faker::Time.between DateTime.now.prev_year,
                            DateTime.now.next_year
      end
    end

    # Field representing a hash of multiple values
    class HashField < Field
      def initialize(name, size = 1, **options)
        super(name, size, **options)
      end
    end

    # Field holding a unique identifier
    class IDField < Field
      alias_method :entity, :parent

      def initialize(name, **options)
        super(name, 16, **options)
        @primary_key = true
      end

      # Return the String parameter as-is
      def self.value_from_string(string)
        string
      end

      # nil value which is interpreted by the backend as requesting a new ID
      def random_value
        nil
      end
    end

    # Field holding a foreign key to another entity
    class ForeignKeyField < IDField
      attr_reader :entity, :relationship
      attr_accessor :reverse

      def initialize(name, entity, **options)
        @relationship = options.delete(:relationship) || :one
        super(name, **options)
        @primary_key = false
        @entity = entity
      end

      # The number of entities associated with the foreign key,
      # or a manually set cardinality
      def cardinality
        @entity.count || super
      end
    end
  end
end
