class KPeg::StringEscape
  # :stopdoc:

    # This is distinct from setup_parser so that a standalone parser
    # can redefine #initialize and still have access to the proper
    # parser setup code.
    def initialize(str, debug=false)
      setup_parser(str, debug)
    end



    # Prepares for parsing +str+.  If you define a custom initialize you must
    # call this method before #parse
    def setup_parser(str, debug=false)
      set_string str, 0
      @memoizations = Hash.new { |h,k| h[k] = {} }
      @result = nil
      @failed_rule = nil
      @failing_rule_offset = -1
      @line_offsets = nil

      setup_foreign_grammar
    end

    attr_reader :string
    attr_reader :failing_rule_offset
    attr_accessor :result, :pos

    def current_column(target=pos)
      if string[target] == "\n" && (c = string.rindex("\n", target-1) || -1)
        return target - c
      elsif c = string.rindex("\n", target)
        return target - c
      end

      target + 1
    end

    def position_line_offsets
      unless @position_line_offsets
        @position_line_offsets = []
        total = 0
        string.each_line do |line|
          total += line.size
          @position_line_offsets << total
        end
      end
      @position_line_offsets
    end

    if [].respond_to? :bsearch_index
      def current_line(target=pos)
        if line = position_line_offsets.bsearch_index {|x| x > target }
          return line + 1
        elsif target == string.size
          past_last = !string.empty? && string[-1]=="\n" ? 1 : 0
          return position_line_offsets.size + past_last
        end
        raise "Target position #{target} is outside of string"
      end
    else
      def current_line(target=pos)
        if line = position_line_offsets.index {|x| x > target }
          return line + 1
        elsif target == string.size
          past_last = !string.empty? && string[-1]=="\n" ? 1 : 0
          return position_line_offsets.size + past_last
        end
        raise "Target position #{target} is outside of string"
      end
    end

    def current_character(target=pos)
      if target < 0 || target > string.size
        raise "Target position #{target} is outside of string"
      elsif target == string.size
        ""
      else
        string[target, 1]
      end
    end

    KpegPosInfo = Struct.new(:pos, :lno, :col, :line, :char)

    def current_pos_info(target=pos)
      l = current_line target
      c = current_column target
      ln = get_line(l-1)
      chr = string[target,1]
      KpegPosInfo.new(target, l, c, ln, chr)
    end

    def lines
      string.lines
    end

    def get_line(no)
      loff = position_line_offsets
      if no < 0
        raise "Line No is out of range: #{no} < 0"
      elsif no >= loff.size
        raise "Line No is out of range: #{no} >= #{loff.size}"
      end
      lend = loff[no]-1
      lstart = no > 0 ? loff[no-1] : 0
      string[lstart..lend]
    end



    def get_text(start)
      @string[start..@pos-1]
    end

    # Sets the string and current parsing position for the parser.
    def set_string string, pos
      @string = string
      @string_size = string ? string.size : 0
      @pos = pos
      @position_line_offsets = nil
    end

    def show_pos
      width = 10
      if @pos < width
        "#{@pos} (\"#{@string[0,@pos]}\" @ \"#{@string[@pos,width]}\")"
      else
        "#{@pos} (\"... #{@string[@pos - width, width]}\" @ \"#{@string[@pos,width]}\")"
      end
    end

    def failure_info
      l = current_line @failing_rule_offset
      c = current_column @failing_rule_offset

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "line #{l}, column #{c}: failed rule '#{info.name}' = '#{info.rendered}'"
      else
        "line #{l}, column #{c}: failed rule '#{@failed_rule}'"
      end
    end

    def failure_caret
      p = current_pos_info @failing_rule_offset
      "#{p.line.chomp}\n#{' ' * (p.col - 1)}^"
    end

    def failure_character
      current_character @failing_rule_offset
    end

    def failure_oneline
      p = current_pos_info @failing_rule_offset

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        "@#{p.lno}:#{p.col} failed rule '#{info.name}', got '#{p.char}'"
      else
        "@#{p.lno}:#{p.col} failed rule '#{@failed_rule}', got '#{p.char}'"
      end
    end

    class ParseError < RuntimeError
    end

    def raise_error
      raise ParseError, failure_oneline
    end

    def show_error(io=STDOUT)
      error_pos = @failing_rule_offset
      p = current_pos_info(error_pos)

      io.puts "On line #{p.lno}, column #{p.col}:"

      if @failed_rule.kind_of? Symbol
        info = self.class::Rules[@failed_rule]
        io.puts "Failed to match '#{info.rendered}' (rule '#{info.name}')"
      else
        io.puts "Failed to match rule '#{@failed_rule}'"
      end

      io.puts "Got: #{p.char.inspect}"
      io.puts "=> #{p.line}"
      io.print(" " * (p.col + 2))
      io.puts "^"
    end

    def set_failed_rule(name)
      if @pos > @failing_rule_offset
        @failed_rule = name
        @failing_rule_offset = @pos
      end
      nil
    end

    attr_reader :failed_rule

    def match_string(str)
      len = str.size
      if @string[pos,len] == str
        @pos += len
        return str
      end

      return nil
    end

    def scan(reg)
      if m = reg.match(@string, @pos)
        @pos = m.end(0)
        return true
      end

      return nil
    end

    if "".respond_to? :ord
      def get_byte
        if @pos >= @string_size
          return nil
        end

        s = @string[@pos].ord
        @pos += 1
        s
      end
    else
      def get_byte
        if @pos >= @string_size
          return nil
        end

        s = @string[@pos]
        @pos += 1
        s
      end
    end

    def sequence(pos, action)
      @pos = pos  unless action
      action ? true : nil
    end

    def look_ahead(pos, action)
      @pos = pos
      action ? true : nil
    end

    def look_negation(pos, action)
      @pos = pos
      action ? nil : true
    end

    def loop_range(range, store)
      _ary = [] if store
      max = range.end && range.max
      count = 0
      save = @pos
      while (!max || count < max) && yield
        count += 1
        if store
          _ary << @result
          @result = nil
        end
      end
      if range.include?(count)
        @result = _ary if store
        true
      else
        @pos = save
        nil
      end
    end

    def parse(rule=nil)
      # We invoke the rules indirectly via apply
      # instead of by just calling them as methods because
      # if the rules use left recursion, apply needs to
      # manage that.

      if !rule
        apply(:_root)
      else
        method = rule.gsub("-","_hyphen_")
        apply :"_#{method}"
      end
    end

    class MemoEntry
      def initialize(ans, pos)
        @ans = ans
        @pos = pos
        @result = nil
        @set = false
        @left_rec = false
      end

      attr_reader :ans, :pos, :result, :set
      attr_accessor :left_rec

      def move!(ans, pos, result)
        @ans = ans
        @pos = pos
        @result = result
        @set = true
        @left_rec = false
      end
    end

    def external_invoke(other, rule, *args)
      old_pos = @pos
      old_string = @string

      set_string other.string, other.pos

      begin
        if val = __send__(rule, *args)
          other.pos = @pos
          other.result = @result
        else
          other.set_failed_rule "#{self.class}##{rule}"
        end
        val
      ensure
        set_string old_string, old_pos
      end
    end

    def apply_with_args(rule, *args)
      @result = nil
      memo_key = [rule, args]
      if m = @memoizations[memo_key][@pos]
        @pos = m.pos
        if !m.set
          m.left_rec = true
          return nil
        end

        @result = m.result

        return m.ans
      else
        m = MemoEntry.new(nil, @pos)
        @memoizations[memo_key][@pos] = m
        start_pos = @pos

        ans = __send__ rule, *args

        lr = m.left_rec

        m.move! ans, @pos, @result

        # Don't bother trying to grow the left recursion
        # if it's failing straight away (thus there is no seed)
        if ans and lr
          return grow_lr(rule, args, start_pos, m)
        else
          return ans
        end
      end
    end

    def apply(rule)
      @result = nil
      if m = @memoizations[rule][@pos]
        @pos = m.pos
        if !m.set
          m.left_rec = true
          return nil
        end

        @result = m.result

        return m.ans
      else
        m = MemoEntry.new(nil, @pos)
        @memoizations[rule][@pos] = m
        start_pos = @pos

        ans = __send__ rule

        lr = m.left_rec

        m.move! ans, @pos, @result

        # Don't bother trying to grow the left recursion
        # if it's failing straight away (thus there is no seed)
        if ans and lr
          return grow_lr(rule, nil, start_pos, m)
        else
          return ans
        end
      end
    end

    def grow_lr(rule, args, start_pos, m)
      while true
        @pos = start_pos
        @result = m.result

        if args
          ans = __send__ rule, *args
        else
          ans = __send__ rule
        end
        return nil unless ans

        break if @pos <= m.pos

        m.move! ans, @pos, @result
      end

      @result = m.result
      @pos = m.pos
      return m.ans
    end

    class RuleInfo
      def initialize(name, rendered)
        @name = name
        @rendered = rendered
      end

      attr_reader :name, :rendered
    end

    def self.rule_info(name, rendered)
      RuleInfo.new(name, rendered)
    end


  # :startdoc:


  attr_reader :text


  # :stopdoc:
  def setup_foreign_grammar; end

  # segment = (< /[\w ]+/ > { text } | "\\" { "\\\\" } | "\n" { "\\n" } | "\r" { "\\r" } | "\t" { "\\t" } | "\b" { "\\b" } | "\"" { "\\\"" } | < . > { text })
  def _segment
    ( # choice
      sequence(self.pos,  # sequence
        ( _text_start = self.pos
          scan(/\G(?-mix:[\w ]+)/) &&
          ( text = get_text(_text_start); true )
        ) &&
        ( @result = (text); true )  # end sequence
      ) ||
      sequence(self.pos,  # sequence
        match_string("\\") &&
        ( @result = ("\\\\"); true )  # end sequence
      ) ||
      sequence(self.pos,  # sequence
        match_string("\n") &&
        ( @result = ("\\n"); true )  # end sequence
      ) ||
      sequence(self.pos,  # sequence
        match_string("\r") &&
        ( @result = ("\\r"); true )  # end sequence
      ) ||
      sequence(self.pos,  # sequence
        match_string("\t") &&
        ( @result = ("\\t"); true )  # end sequence
      ) ||
      sequence(self.pos,  # sequence
        match_string("\b") &&
        ( @result = ("\\b"); true )  # end sequence
      ) ||
      sequence(self.pos,  # sequence
        match_string("\"") &&
        ( @result = ("\\\""); true )  # end sequence
      ) ||
      sequence(self.pos,  # sequence
        ( _text_start = self.pos
          get_byte &&
          ( text = get_text(_text_start); true )
        ) &&
        ( @result = (text); true )  # end sequence
      )
      # end choice
    ) or set_failed_rule :_segment
  end

  # root = segment*:s { @text = s.join }
  def _root
    sequence(self.pos,  # sequence
      loop_range(0.., true) {
        apply(:_segment)
      } &&
      ( s = @result; true ) &&
      ( @result = (@text = s.join); true )  # end sequence
    ) or set_failed_rule :_root
  end

  # embed_seg = ("#" { "\\#" } | segment)
  def _embed_seg
    ( # choice
      sequence(self.pos,  # sequence
        match_string("#") &&
        ( @result = ("\\#"); true )  # end sequence
      ) ||
      apply(:_segment)
      # end choice
    ) or set_failed_rule :_embed_seg
  end

  # embed = embed_seg*:s { @text = s.join }
  def _embed
    sequence(self.pos,  # sequence
      loop_range(0.., true) {
        apply(:_embed_seg)
      } &&
      ( s = @result; true ) &&
      ( @result = (@text = s.join); true )  # end sequence
    ) or set_failed_rule :_embed
  end

  Rules = {}
  Rules[:_segment] = rule_info("segment", "(< /[\\w ]+/ > { text } | \"\\\\\" { \"\\\\\\\\\" } | \"\\n\" { \"\\\\n\" } | \"\\r\" { \"\\\\r\" } | \"\\t\" { \"\\\\t\" } | \"\\b\" { \"\\\\b\" } | \"\\\"\" { \"\\\\\\\"\" } | < . > { text })")
  Rules[:_root] = rule_info("root", "segment*:s { @text = s.join }")
  Rules[:_embed_seg] = rule_info("embed_seg", "(\"\#\" { \"\\\\\#\" } | segment)")
  Rules[:_embed] = rule_info("embed", "embed_seg*:s { @text = s.join }")
  # :startdoc:
end
