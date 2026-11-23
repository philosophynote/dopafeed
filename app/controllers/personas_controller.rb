class PersonasController < ApplicationController
  before_action :set_persona, only: %i[edit update]

  def index
    @personas = Persona.ordered
  end

  def edit
  end

  def update
    if @persona.update(params.expect(persona: %i[name title color description system_prompt]))
      redirect_to personas_path, status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_persona
    @persona = Persona.find(params[:id])
  end
end
