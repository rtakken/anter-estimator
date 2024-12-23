class ChatBotController < ApplicationController
  def index
    @conversations = current_user.conversations
  end

  def show
    @conversation = current_user.conversations.find(params[:id])
    @messages = @conversation.messages
  end

  def new
    @conversation = current_user.conversations.create(title: "New Conversation")
    redirect_to chat_bot_path(@conversation)
  end

  def destroy
    @conversation = current_user.conversations.find(params[:id])
    @conversation.destroy
    redirect_to chat_bot_index_path
  end

  def create
    @conversation = current_user.conversations.find(params[:id])
    
    adapter = Intelligence::Adapter.build :google do
      key   ENV.fetch("GOOGLE_API_KEY", nil)
      chat_options do
        model "gemini-1.5-flash"
        max_tokens 256
      end
    end

    weather_tool = Intelligence::Tool.build! do
      name :get_weather
      description "Get the current weather for a specified location"
      argument name: :location, required: true, type: 'object' do
        description "The location for which to retrieve weather information"
        property name: :city, type: 'string', required: true do
          description "The city or town name"
        end
        property name: :state, type: 'string' do
          description "The state or province (optional)"
        end
        property name: :country, type: 'string' do
          description "The country (optional)"
        end
      end
    end

    request = Intelligence::ChatRequest.new(adapter: adapter)

    # Create user message
    user_message = @conversation.messages.create!(
      role: 'user',
      content: params[:message]
    )

    tools = []
    # Prepare conversation history for AI
    ai_conversation = Intelligence::Conversation.build do
      system_message do
        content text: "You are a highly efficient AI assistant. Provide clear, concise responses."
      end
      tools << weather_tool
    end

    # # Add all existing messages to the AI conversation
    @conversation.messages.each do |msg|
      message = Intelligence::Message.new(msg.role.to_sym)
      message << Intelligence::MessageContent::Text.new(text: msg.content)
      ai_conversation.messages << message
    end

    # Handle photo upload if present
    if params[:photo].present?
      photo_message = Intelligence::Message.new(:user)
      photo_message << Intelligence::MessageContent::Binary.new(
        bytes: params[:photo].read,
        content_type: params[:photo].content_type
      )
      ai_conversation.messages << photo_message
    end

    response = request.chat(ai_conversation)
    if response.success?
      response.result.choices.each do |choice|
        choice.message.each_content do |content|
          debugger
          if content.is_a?(Intelligence::MessageContent::ToolCall)
            # Process the tool call
            if content.tool_name == :get_weather
              # Make actual weather API call here
              weather_data = fetch_weather(content.tool_parameters[:location])

              # Send tool result back to continue the conversation
              conversation.messages << Intelligence::Message.build! do
                role :user
                content do
                  type :tool_result
                  tool_call_id content.tool_call_id
                  tool_result weather_data.to_json
                end
              end
            end
          end
        end
      end
      assistant_message = response.result.message
      # Save the AI response to our database
      @conversation.messages.create!(
        role: 'assistant',
        content: assistant_message.contents.first.text
      )
    else
      flash[:error] = "Error: #{response.result.error_description}"
    end

    redirect_to chat_bot_path(@conversation)  
  end
end
