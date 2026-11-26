class PersonasController < ApplicationController
  before_action :set_persona, only: %i[edit update]

  def index
    @personas = Persona.ordered
  end

  def new
    @persona = Persona.new
  end

  def create
    @persona = Persona.new(persona_params)
    if @persona.save
      redirect_to personas_path, status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @persona.update(persona_params)
      redirect_to personas_path, status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_persona
    @persona = Persona.find(params[:id])
  end

  def persona_params
    params.expect(persona: %i[name title color description system_prompt])
  end
end
