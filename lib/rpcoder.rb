# encoding: utf-8

class String
  def pascalize
    # PascalCase ('_'で分割し、各頭文字を大文字化したあと結合)
    self.split('_').map{|s| s.capitalize}.join
  end

  def camelize
    # camelCase (self.pascalizeを呼び出し、先頭を小文字化)
    self.pascalize.sub(/^([A-Z])/, self[0, 1].downcase)
  end

  def to_snake
    # snake_case (大文字を小文字にして'_'を付ける, ただし先頭は対象外)
    self.gsub(/^.+([A-Z])/, '_' + self[0, 1].downcase)
  end
end

require 'erb'
require 'rpcoder/function'
require 'rpcoder/type'
require 'rpcoder/enum'

module RPCoder
  class << self
    def name_space=(name_space)
      @name_space = name_space
    end

    def name_space
      @name_space
    end

    def api_class_name=(name)
      @api_class_name = name
    end

    def api_class_name
      @api_class_name
    end

    def types
      @types ||= []
    end

    def type(name)
      type = Type.new
      type.name = name
      yield type
      types << type
      type
    end

    def functions
      @functions ||= []
    end

    def function(name)
      func = Function.new
      func.name = name
      yield func
      functions << func
      func
    end

    def enums
      @enums ||= []
    end

    def enums_hash
      @enums_hash ||= {}
    end

    def enum(name)
      enum = Enum.new
      enum.name = name
      yield enum
      enums << enum
      enums_hash[name.to_s] = enum
      enum
    end

    #
    # ファイルを生成する
    #
    # @param string output_dir ファイル生成先ディレクトリ
    #
    def export(output_dir)
      # xml変換用処理は取り除かれました、下記ハッシュでブランチを切ることで、当時の機能を利用することはできます、念のため
      # git show d0adbd16c6305d6a1680700c05ed84c08b5eb9ce

      # functions/type毎クラスの基底クラスを作成する ---------------------------
      version = get_contract_version # コントラクトバージョンを取得する
      {
        'ContractFunctionBase' => 'lib/Contract',
        'ValidateType'         => 'lib/Contract',
        'Enum'                 => 'lib/Contract',
      }.each do |erb_name, parent_dir|
        # ディレクトリを作成する
        dir = File.join(output_dir, parent_dir)
        FileUtils.mkdir_p(dir) # ディレクトリを作成する

        file_path = File.join(dir, erb_name + '.php')
        File.open(file_path, 'w') do |file|
          # bindingに格納するものを羅列
          version = version
          file << render_php(erb_name, binding)
        end
      end

      # RPCoder.function毎にファイル化する -------------------------------------
      {'func' => 'lib/Contract/Function', 'api' => 'public_html/api'}.each do |erb_name, parent_dir|
        # RPCoder.function毎に処理する
        functions.each do |func|
          # ディレクトリを作成する
          func_dir = File.join(parent_dir, func.get_path_without_file_name)
          dir      = File.join(output_dir, func_dir)
          FileUtils.mkdir_p(dir)

          # ファイルを作成する
          if 'api' === erb_name
            make_pathphp(dir, func_dir.split('/').size)
            file_path = File.join(output_dir, parent_dir, func.path)
          else
            file_path = File.join(dir, func.name + '.php')
          end
          File.open(file_path, 'w') do |file|
            # bindingに格納するものを羅列
            func          = func
            api_use_types = get_use_types(func.return_types).uniq # このfunctionで使用されるtypeの配列
            file << render_php(erb_name, binding)
          end
        end
      end

      # RPCoder.type毎にファイル化する -----------------------------------------
      {'type' => 'lib/Contract/Type'}.each do |erb_name, parent_dir|
        # RPCoder.type毎に処理する
        types.each do |type|
          # ディレクトリを作成する
          dir = File.join(output_dir, parent_dir)
          FileUtils.mkdir_p(dir) # ディレクトリを作成する

          # ファイルを作成する
          file_path = File.join(dir, type.name + '.php')
          File.open(file_path, 'w') do |file|
            # bindingに格納するものを羅列
            type = type
            file << render_php(erb_name, binding)
          end
        end
      end
    end

    #
    # path.phpがなければ作成する
    #
    # @param string dir   ディレクトリ
    # @param int    depth 深さ
    #
    def make_pathphp(dir, depth)
      file_path = File.join(dir, 'path.php')
      unless File.exist?(file_path)
        File.open(file_path, 'w') do |file|
          # bindingに格納するものを羅列
          depth = depth
          file << render_php('path', binding)
        end
      end
    end

    #
    # ファイルを書き出す
    #
    # @param string erb_name erbファイル名の一部
    # @param object _binding 呼び出し元のbindingオブジェクト
    #
    def render_php(erb_name, _binding)
      render_erb("php_#{erb_name}.erb", _binding)
    end

    #
    # コントラクトバージョンを取得する
    #
    # @return string version コントラクトバージョン
    #
    def get_contract_version
      version = ''
      open("| git hash-object #{File.join($PROGRAM_NAME)}") do |f|
        version = f.gets.strip
        puts "This Contract Hash (Version) is \"#{version}\""
      end
      version
    end

    #
    # 特定のfunctionで使用されるtypeの配列を取得する
    #
    # @param  object fields    最初呼び出しではfunc.return_types、再帰呼び出しではtype.fields
    # @return array  use_types 使用されるtypeの配列
    #
    def get_use_types(fields)
      use_types = []

      fields.each do |field|
        unless field.builtin_type?
          types.each do |type|
            if type.name.to_s === field.type.to_s
              use_types.push(field.type.to_s)              # 保持
              use_types.concat(get_use_types(type.fields)) # 再帰
            end
          end
        end
      end

      use_types
    end

    def render_erb(template, _binding)
      ERB.new(File.read(template_path(template)), nil, '-').result(_binding)
    end

    def template_path(name)
      File.join File.dirname(__FILE__), 'templates/php_tpl', name
    end

    def dir_to_export_classes(dir)
      File.join(dir, *name_space.split('.'))
    end

    def clear
      functions.clear
      types.clear
    end

    # クライアントチームが使用する関数であるため、こちらではダミー
    def add_template(dummy1, dummy2)
    end

    def output_path=(dummy)
    end

    def templates_path=(dummy)
    end
  end
end
