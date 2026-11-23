class PersonasController < ApplicationController
  def index
    @personas = Persona.ordered
  end
end
