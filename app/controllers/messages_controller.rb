class MessagesController < ApplicationController
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

    user_message = @conversation.messages.create!(message_params)


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
    if message_params[:image].present?
      image_message = Intelligence::Message.new(:user)
      image_message << Intelligence::MessageContent::Binary.new(
        bytes: user_message.image.download,
        content_type: user_message.image.content_type
      )
      ai_conversation.messages << image_message
    end

    response = request.chat(ai_conversation)
    if response.success?
      response.result.choices.each do |choice|
        choice.message.each_content do |content|
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

    redirect_to conversation_path(@conversation)
  end

  private
  def message_params
    params.require(:message).permit(:content, :image, :role)
  end
end
