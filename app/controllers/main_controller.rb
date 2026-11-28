class MainController < ApplicationController
  include TodayStatus

  def show
    @feed_unread_counts = Article.unread.group(:feed_id).count
    @unread_count = @feed_unread_counts.values.sum
    @filter_feeds = Feed.where(id: @feed_unread_counts.keys).sort_by { |feed| [ -@feed_unread_counts[feed.id], feed.id ] }
    @filtering = params[:feed].present?
    @current_feed = Feed.find_by(id: params[:feed]) if params[:feed].is_a?(String)
    @filter_feeds |= [ @current_feed ] if @current_feed
    @next_feed = (@filter_feeds - [ @current_feed ]).first if @current_feed
    articles = Article.unread.newest_first.includes(:feed)
    @articles = (@filtering ? articles.where(feed: @current_feed) : articles).load
    load_today_status
  end
end
