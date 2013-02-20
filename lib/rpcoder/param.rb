module RPCoder
  class Param
    def self.original_types
      [:int, :Int, :double, :Double, :string, :bool, :Boolean, :String, :Array]
    end

    attr_accessor :name, :type, :options
    def initialize(name, type, options = {})
      @name = name
      @type = type
      @options = options
    end

    def array?
      options[:array?]
    end

    def array_or_type
      if array?
        "Array"
      else
        type
      end
    end

    def original_type?
      Param.original_types.include?(type.to_sym)
    end
    alias :builtin_type? :original_type?

    def array_param
      Param.new(name, options[:array_type])
    end

    def instance_creator(elem = 'elem', options = {})
      elem = element_accessor(elem, options)
      if original_type?
        elem
      else
        "new #{type}(#{elem})"
      end
    end

    def element_accessor(elem = 'elem', options = {})
      if options[:object?]
        "object['#{elem}']"
      else
        elem
      end
    end

    def option_require?
      if options[:require].nil?
        return true
      else
        options[:require]
      end
    end

    def option_escape?
      options[:htmlescape]
    end

    # パラメータのオプションをphp配列に変換する
    def options_to_php_array
      str = ""

      options.each do |key, val|
        case key.to_s
        when :array?.to_s
          # array?のとき、[?]を取り除いて追加する
          str += "'array' => #{val.to_s}, "
        when "require", "max", "min", "length", "ngword", "htmlescape"
          # 数値や真偽のとき、何もせずに追加する
          str += "'#{key.to_s}' => #{val.to_s}, "
        else
          # 文字などのとき、値をクォーテーションで囲み追加する
          str += "'#{key.to_s}' => '#{val.to_s}', "
        end
      end

      unless str.empty?
        # 空でないとき
        str = "array(#{str.sub(/, $/, '')})" # 最後の[, ]を取り除いて配列化
      end

      str
    end
  end
end
