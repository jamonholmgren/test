module Yapper::Document
  module Relation
    extend MotionSupport::Concern

    included do
      class << self
        attr_accessor :relations
      end

      self.relations = {}
      self.relations[:has_many] = []
      self.relations[:belongs_to] = []
    end

    module ClassMethods
      def has_many(relation, options={})
        self.relations[:has_many] << { relation => options } unless self.relations[:has_many].find { |r,o| r == relation }

        define_method(relation) do
          Object.qualified_const_get(relation.to_s.singularize.camelize).where("#{self._type.underscore}_id".to_sym => self.id)
        end

        define_method("#{relation}=") do |docs|
          raise "You must pass an array of objects or attributes" unless docs.is_a?(Array)
          raise "All elements in the array must be of the same type" unless docs.all? { |doc| doc.is_a?(docs.first.class) }

          changes = {}
          Yapper::Sync.disabled do
            db.execute do |txn|
              docs.each do |doc|
                if doc.is_a?(Yapper::Document)
                  if doc.persisted?
                    doc.update_attributes("#{self._type.underscore}" => self)
                    changes["#{relation.singularize}_ids"] ||= []
                    changes["#{relation.singularize}_ids"] << doc.id
                  else
                    doc.assign_attributes("#{self._type.underscore}" => self)

                    changes[relation] ||= []
                    changes[relation] << doc.attributes

                    doc.save
                  end
                elsif doc.is_a?(Hash)
                  doc = doc.with_indifferent_access

                  klass = Object.qualified_const_get(relation.singularize.to_s.camelize)
                  instance = klass.find(doc[:id]) if doc[:id]
                  instance ||= klass.new
                  instance.assign_attributes("#{self._type.underscore}" => self)
                  instance.assign_attributes(doc)

                  changes[relation] ||= []
                  changes[relation] << instance.attributes

                  instance.save
                else
                  raise "Must pass either attributes or an object"
                end
              end
            end
            @changes.merge!(changes)
          end
        end
      end

      def belongs_to(relation, options={})
        fk_field = "#{relation}_id".to_sym
        self.relations[:belongs_to] << { relation => options } unless self.relations[:belongs_to].find { |r,o| r == relation }
        self.field(fk_field, :type => String)
        self.index(fk_field)

        define_method(relation) do
          instance_variable_get("@#{relation}") || Object.qualified_const_get(relation.to_s.camelize).find(self.send("#{relation}_id"))
        end

        define_method("#{relation}=") do |parent|
          self.instance_variable_set("@#{relation}", parent)
          self.send("#{relation}_id=", parent.id)
        end
      end
    end
  end
end
