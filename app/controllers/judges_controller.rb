class JudgesController < ApplicationController
  before_action :set_judge, only: [:show, :edit, :update, :destroy]

  # GET /judges
  # GET /judges.json
  def index
    authorize Judge
    @judges = Judge.all
  end

  # GET /judges/1
  # GET /judges/1.json
  def show
  end

  # GET /judges/new
  def new
    authorize Judge
    @judge = Judge.new
  end

  # GET /judges/1/edit
  def edit
  end

  # POST /judges
  # POST /judges.json
  def create
    authorize Judge
    @judge = Judge.new(permitted_attributes(Judge))

    respond_to do |format|
      if @judge.save
        format.html { redirect_to @judge, notice: I18n.t('controllers.created', model: Judge.model_name.human) }
        format.json { render :show, status: :created, location: @judge }
      else
        format.html { render :new }
        format.json { render json: @judge.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /judges/1
  # PATCH/PUT /judges/1.json
  def update
    respond_to do |format|
      if @judge.update(permitted_attributes(Judge))
        format.html { redirect_to @judge, notice: I18n.t('controllers.updated', model: Judge.model_name.human) }
        format.json { render :show, status: :ok, location: @judge }
      else
        format.html { render :edit }
        format.json { render json: @judge.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /judges/1
  # DELETE /judges/1.json
  def destroy
    @judge.destroy
    respond_to do |format|
      format.html { redirect_to judges_url, notice: I18n.t('controllers.destroyed', model: Judge.model_name.human) }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_judge
    @judge = Judge.find(params[:id])
    authorize @judge
  end
end