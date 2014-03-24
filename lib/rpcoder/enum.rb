require 'rpcoder/param'

module RPCoder
  class Enum
    attr_accessor :name, :description, :flags, :array_type

    def initialize
      @num = 0
    end

    def constants
      @constants ||= []
    end

    def flags?
      @flags
    end

    def add_constant(name, options = {})
      if self.flags? and @num == 0
        @num = 1
      end
      if options[:num]
        @num = options[:num]
      end
      constants << EnumItem.new(name, @num, options)
      if self.flags?
        @num *= 2
      else
        @num += 1
      end
      constants
    end

    def get_php_arr
      str = 'array('
      constants.each do |enum_item|
        str += enum_item.num.to_s + ', '
      end
      str += ')'
    end

    def get_min
      if flags?
        return 0
      else
        min = nil
        constants.each do |enum_item|
          if min.nil? or min > enum_item.num
            min = enum_item.num
          end
        end
        return min
      end
    end

    def get_max
      if flags?
        sum = 0;
        constants.each do |enum_item|
          sum += enum_item.num
        end
        return sum
      else
        max = nil
        constants.each do |enum_item|
          if max.nil? or max < enum_item.num
            max = enum_item.num
          end
        end
        return max
      end
    end

    class EnumItem
      attr_accessor :name, :num, :options, :description

      def initialize(name, num, options = {})
        @name = name
        @num = num
        @options = options
        @description = options[:desc] if options[:desc]
      end
    end
  end
end
