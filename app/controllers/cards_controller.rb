class CardsController < ApplicationController
  def show
    @card = Reading.completed.includes(article: %i[feed judgment]).find(params[:id])
    @unread_count = unread_count
  end
end
