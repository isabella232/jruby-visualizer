require 'jrubyfx'

class CompilerData
  include JRubyFX
  
  @@ir_builder = nil
  
  property_accessor :ruby_code, :ast_root, :ir_scope, :current_pass, :next_pass
  
  def self.parse(code)
    JRuby.parse(code)
  end
  
  def self.create_ir_builder
    JRuby::IR.compiler_debug = true
    ir_manager = JRuby::runtime.ir_manager
    ir_manager.dry_run = true

    builder = 
      if JRuby::runtime.is1_9?
      org.jruby.ir.IRBuilder19
    else
      org.jruby.ir.IRBuilder
    end
    builder.new(ir_manager)
  end
  
  def self.build_ir(root_node)
    unless @@ir_builder
      @@ir_builder = create_ir_builder
    end
    @@ir_builder.build_root(root_node)
  end
  
  def self.pass_to_s(pass)
    pass.class.to_s.split("::").last
  end
  
  def self.compiler_passes_names
    scheduler = JRuby::runtime.ir_manager.schedule_passes
    scheduler.map do |pass|
      pass_to_s(pass)
    end
  end
  
  def reset_scheduler
    ir_manager = JRuby::runtime.ir_manager
    @scheduler = ir_manager.schedule_passes.iterator
    if @scheduler.has_next
      @current_pass = nil
      @next_pass = @scheduler.next
    else
      @current_pass = @next_pass = nil
    end    
  end
  
  def initialize(ruby_code='')
    @ruby_code = SimpleStringProperty.new(ruby_code)
    @ast_root = SimpleObjectProperty.new(self, "ast_root", self.class.parse(ruby_code))
    @ir_scope = SimpleObjectProperty.new(self, "ir_scope", self.class.build_ir(@ast_root.get))
    # bind change of Ruby code to reparsing an AST and set the property
    ruby_code_property.add_change_listener do |new_code|
      @ast_root = self.class.parse(new_code)
    end
    # bind change of AST to rebuilding IR and set the property
    ast_root_property.add_change_listener do |new_ast|
      @ir_scope = self.class.build_ir(new_ast)
    end
    
    # initialize scheduler
    reset_scheduler
  end
  
  def self.run_pass_on_all_scopes(pass, scope)
    pass.run(scope)
    scope.lexical_scopes.each do |lex_scope|
      run_pass_on_all_scopes(pass, lex_scope)
    end
  end
  
  def step_ir_passes
    if @next_pass
      @current_pass = @next_pass
      @next_pass = 
        if @scheduler.has_next
          @scheduler.next
        else
          nil
      end
      self.class.run_pass_on_all_scopes(@current_pass, @ir_scope.get)
      puts "Executed #{@current_pass.java_class}"
      ir_scope_property.fire_value_changed_event
    end
  end

end
