class ListsController < ApplicationController
  def index
    @lists = List.order_by_created.to_a
    @todo_counts = todo_counts
    @orphan_count = Todo.orphaned.count
    @owner = params[:owner].presence
    @lists = @lists.select { |list| list.owner_id == @owner } if @owner

    respond_to do |format|
      format.html
      format.json { render json: @lists.map { |list| stored_attrs(list) } }
    end
  end

  def show
    @list = List.where(id: params[:id]).first or return head(:not_found)
    @todos = @list.todos.to_a

    respond_to do |format|
      format.html
      format.json { render json: stored_attrs(@list).merge("todos" => @todos.map { |todo| stored_attrs(todo) }) }
    end
  end

  private

  def todo_counts
    Todo.all.pluck(:list_id).tally
  end
end
