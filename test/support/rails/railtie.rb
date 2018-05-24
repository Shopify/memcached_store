module Rails
  class Railtie
    class Initializer < Struct.new(:name, :block)
      def run
        block.call
      end
    end

    class_attribute :initializers
    self.initializers = []

    def self.initializer(name, &block)
      initializers << Initializer.new(name, block)
    end
  end
end
