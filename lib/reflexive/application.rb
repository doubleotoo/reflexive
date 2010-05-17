require "sinatra/base"
require "sinatra/reloader" if ENV["SINATRA_RELOADER"]
require "sinatra_more/markup_plugin"

require "coderay"
require "ostruct"
require "open-uri"

require "reflexive/faster_open_struct"
require "reflexive/helpers"
require "reflexive/columnizer"
require "reflexive/constantize"
require "reflexive/descendants"
require "reflexive/methods"

if ENV["SINATRA_RELOADER"]
  require "rails/all"
  require "arel"

  module ::Kernel
    def r(*args)
      raise((args.size == 1 ? args[0] : args).inspect)
    end
  end
end

module Reflexive
  class Application < Sinatra::Base
    register SinatraMore::MarkupPlugin
    include Reflexive::Helpers

    configure(:development) do
      if ENV["SINATRA_RELOADER"]
        register Sinatra::Reloader
        also_reload "lib/**/*.rb"
      end
    end    

    class << self
      def root
        require "pathname"
        Pathname("../../../").expand_path(__FILE__)
      end
    end

    set :public, self.root + "public"
    set :views, self.root + "views"

    def self.action(path, &block)
      get("/reflexive/#{ path }", &block)
    end

    def e(message)
      @message = message
      erb :error
    end

    action "dashboard" do
      erb :dashboard
    end

    action "constant_lookup" do
      if klass = Reflexive.constant_lookup(*params.values_at(:name, :scope))
        redirect(constant_path(klass.to_s))
      else
        e "failed to lookup constant `#{ params[:name] }' in scope #{ params[:scope] }"
      end
    end

    action "files/*" do |path|
      @path = "/" + path
      if File.stat(@path).directory?
        erb :directories_show
      else
        @source = highlight_file(@path)
        erb :files_show
      end
    end

    get "/reflexive/load_path_lookup" do
      path = params[:path]
      feature = Reflexive.loaded_features_lookup(path) || Reflexive.load_path_lookup(path)
      if feature
        redirect(file_path(feature))
      else
        e "failed to find feature: #{ path }"
      end
    end

    get %r</reflexive/constants/([^/&#]+)/class_methods/([^/&#]+)/definition> do |klass, method|
      find_klass(klass)
      @method_name = method
      @path, @line = @klass.method(@method_name).source_location
      @source = highlight_file(@path, :highlight_lines => [@line])
      erb :methods_definition
    end

    get %r</reflexive/constants/([^/&#]+)/instance_methods/([^/&#]+)/definition> do |klass, method|
      find_klass(klass)
      @method_name = method
      @path, @line = @klass.instance_method(@method_name).source_location
      @source = highlight_file(@path, :highlight_lines => [@line])
      erb :methods_definition
    end

    get %r</reflexive/constants/([^/&#]+)/methods/([^/&#]+)/apidock> do |klass, method|
      find_klass(klass)
      @method_name = method
      erb :methods_apidock
    end

    get %r</reflexive/constants/([^/&#]+)/class_methods/([^/&#]+)> do |klass, method|
      find_klass(klass)
      begin
        if @klass.method(method).source_location
          redirect(class_method_definition_path(klass, method) +
                  "#highlighted")
        else
          redirect(method_documentation_path(klass, method))
        end
      rescue NameError
        e "failed to find `#{ method }' class method for #{ klass }"
      end
    end

    get %r</reflexive/constants/([^/&#]+)/instance_methods/([^/&#]+)> do |klass, method|
      find_klass(klass)
      begin
        if @klass.instance_method(method).source_location
          redirect(instance_method_definition_path(klass, method) +
                  "#highlighted")
        else
          redirect(method_documentation_path(klass, method))
        end
      rescue NameError
        e "failed to find `#{ method }' instance method for #{ klass }"
      end
    end

    get %r</reflexive/constants/([^/&#]+)> do |klass|
      find_klass(klass)

      exclude_trite = ![ BasicObject, Object ].include?(@klass)
      @methods = Reflexive::Methods.new(@klass, :exclude_trite => exclude_trite)

      ancestors_without_self_and_super = @klass.ancestors[2..-1] || []
      class_ancestors = ancestors_without_self_and_super.select { |ancestor| ancestor.class == Class }
      @class_ancestors = class_ancestors if class_ancestors.size > 0
      
      if @klass.respond_to?(:superclass) &&
          @klass.superclass != Object &&
          @klass.superclass != nil
        @superclass = @klass.superclass  
      end

      erb :constants_show
    end

    protected

    error(404) { @app.call(env) if @app }

    def find_klass(klass = params[:klass])
      @klass = Reflexive.constantize(klass) if klass 
    end
  end
end