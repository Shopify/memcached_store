module Rails
  def self.logger
    @logger ||= Logger.new("/dev/null")
  end

  def self.env
    Struct.new("Env") do
      def self.test?
        true
      end
    end
  end
end
