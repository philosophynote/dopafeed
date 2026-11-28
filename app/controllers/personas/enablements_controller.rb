module Personas
  class EnablementsController < ApplicationController
    def update
      @persona = Persona.find(params[:persona_id])
      @persona.update!(enabled: params.expect(:enabled))

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to personas_path, status: :see_other }
      end
    end

    private

    def authentication_return_url
      personas_url
    end
  end
end
