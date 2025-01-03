class ConversationsController < ApplicationController
  def index
    @conversations = current_user.conversations
  end

  def show
    @conversation = current_user.conversations.find(params[:id])
    @message = Message.new
    @messages = @conversation.messages
  end

  def new
    @conversation = current_user.conversations.create(title: "New Conversation")
    redirect_to conversation_path(@conversation)
  end

  def destroy
    @conversation = current_user.conversations.find(params[:id])
    @conversation.destroy
    redirect_to conversations_path
  end
end
