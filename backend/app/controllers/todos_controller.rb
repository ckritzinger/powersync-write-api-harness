class TodosController < ApplicationController
  # All todos across all lists and owners; ?orphaned=1 limits to todos whose list_id has no list.
  def index
    scope = params[:orphaned].present? ? Todo.orphaned : Todo.all
    @orphaned = params[:orphaned].present?
    @todos = scope.to_a.sort_by { |t| [t.list_id.to_s, t.position || 0, t.created_at.to_s] }

    respond_to do |format|
      format.html
      format.json { render json: @todos.map { |todo| stored_attrs(todo) } }
    end
  end
end
