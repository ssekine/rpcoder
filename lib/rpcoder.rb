# encoding: utf-8

require 'erb'
require 'rpcoder/function'
require 'rpcoder/type'

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

    def export(dir = nil)
      # 共通出力先パス
      if nil === dir
        root_path = File.expand_path('src', File.dirname($PROGRAM_NAME))
      else
        root_path = dir
      end

      # コントラクトバージョンの取得 -------------------------------------------
      version = ""
      contract_path = File.join($PROGRAM_NAME)
      open("| git hash-object #{contract_path}") do |f|
        version = f.gets.strip # gitコマンドから、コントラクトファイルの最新コミットハッシュを取得する
        puts "This Contract Hash (Version) is \"#{version}\""
      end

      # function毎にファイル化する ---------------------------------------------
      {"func" => "lib/Contract/Function", "api" => "public_html/api"}.each do |erb_name, parent_path|
        if "public_html" ===  parent_path.split("/").fetch(0)
          # public_html配下のとき、path.phpを作成するフラグを立てる
          require_pathphp_flg = true
        end
        dir_path_back = '' # 前回処理したfuncのdir_path

        functions.each do |func|
          project_path = File.join(parent_path.split("/"), func.path.to_s.sub(/[^\/]*\.php/, "").sub(/:.*$/, "").split("/")) # プロジェクトのディレクトリ構造
          dir_path     = File.join(root_path, project_path) # 出力先パスを生成する
          FileUtils.mkdir_p(dir_path)                       # 出力先ディレクトリがなければ作成する

          if true === require_pathphp_flg
            # public_html下にあるとき
            unless dir_path === dir_path_back
              # 前回と違うパスのとき
              make_pathphp(dir_path, project_path) # 出力先ディレクトリにpath.phpがなければ作成する
            end
            dir_path_back = dir_path # 前回処理パスを更新する

            # func.pathの通りに生成する
            file_path = File.join(root_path, parent_path.split("/"), func.path.to_s.sub(/:.*$/, "").split("/"))
          else
            # func.pathのファイル名をfunc.nameに変えて生成する
            file_path = File.join(dir_path, func.name + ".php")
          end

          puts "PHP #{erb_name} : #{file_path}"
          File.open(file_path, "w") do |file| file << render_funcphp(func, erb_name) end
        end
      end

      # type毎にファイル化する -------------------------------------------------
      {"type" => "lib/Contract/Type"}.each do |erb_name, parent_path|
        types.each do |type|
          dir_path  = File.join(root_path, parent_path.split("/")) # 出力先パスを生成する
          file_path = File.join(dir_path, type.name + ".php")      # 出力先ファイル名を生成する
          FileUtils.mkdir_p(dir_path)                              # 出力先ディレクトリがなければ作成する

          puts "PHP #{erb_name} : #{file_path}"
          File.open(file_path, "w") do |file| file << render_typephp(type, erb_name) end
        end
      end

      # functions/typeをひとつのファイルに (継承元になるようなファイルとして) 書き出す
      {"ContractFunctionBase" => "lib/Contract", "ValidateType" => "lib/Contract"}.each do |erb_name, parent_path|
        dir_path  = File.join(root_path, parent_path.split("/")) # 出力先パスを生成する
        file_path = File.join(dir_path, erb_name + ".php")       # 出力先ファイル名を生成する
        FileUtils.mkdir_p(dir_path)                              # 出力先ディレクトリがなければ作成する

        puts "PHP #{erb_name} : #{file_path}"
        File.open(file_path, "w") do |file| file << render_basephp(version, erb_name) end # コントラクトバージョンも渡す
      end
    end

    # function用のファイル生成
    def render_funcphp(func, erb_name)
      # erb内で"func"にアクセス可能
      if "api" === erb_name
        # php_api.erb内で"api_use_types"にアクセス可能 (このfunctionで使用されるtypeの配列)
        api_use_types = get_use_types(func.return_types).uniq
      end

      render_erb("php_#{erb_name}.erb", binding)
    end

    # type用のファイル生成
    def render_typephp(type, erb_name)
      # erb内で"type"にアクセス可能
      render_erb("php_#{erb_name}.erb", binding)
    end

    # function/type共用のファイル生成
    def render_basephp(version, erb_name)
      # erb内で"version"にアクセス可能
      render_erb("php_#{erb_name}.erb", binding)
    end

    #
    # path.phpがなければ作成
    #
    # @param  string  dir_path_make   ファイルを作成するディレクトリ
    # @param  string  dir_path_depth  深さを算出するディレクトリ
    #
    def make_pathphp(dir_path_make, dir_path_depth)
      file_path = File.join(dir_path_make, "path.php")
      puts "path    : #{file_path}" # 出力ファイルパスを表示
      File.open(file_path, "w") do |file| file << render_pathphp(dir_path_depth.split("/").size) end
    end

    # path.php用のファイル生成
    def render_pathphp(depth)
      # erb内で"depth"にアクセス可能
      render_erb("php_path.erb", binding)
    end

    #
    # 特定のfunctionで使用されるtypeの配列を取得する
    #
    # @param   object  fields     最初呼び出しではfunc.return_types、再帰呼び出しではtype.fields
    # @return  array   use_types  使用されるtypeの配列
    #
    def get_use_types(fields)
      use_types = []

      fields.each do |field|
        unless field.builtin_type?
          # 組み込み型でないとき
          use_types.push(field.type.to_s) # それをとっておく
          types.each do |type|
            if type.name.to_s === field.type.to_s
              use_types.concat(get_use_types(type.fields)) # 再帰
            end
          end
        end
      end

      return use_types
    end

    def render_erb(template, _binding)
      ERB.new(File.read(template_path(template)), nil, '-').result(_binding)
    end

    def template_path(name)
      File.join File.dirname(__FILE__), 'templates', name
    end

    def dir_to_export_classes(dir)
      File.join(dir, *name_space.split('.'))
    end

    def clear
      functions.clear
      types.clear
    end

    # クライアントチームが使用する関数であるため、こちらではダミー
    def add_template(dummy1,dummy2)
    end

    def output_path=(dummy)
    end

    def templates_path=(dummy)
    end
  end
end
