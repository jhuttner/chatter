add_typing_user = (username) ->
  $("#users-typing").append("<p><span>" + username + "</span> is typing...</p>")

remove_typing_user = (username) ->
  $.each "#users-typing span", ($el) ->
    if $el.text() == username
      $el.remove()

add_question = (question) ->
  $("#questions").append("<p>" + JSON.dumps(question) + "</p>")

flash_username = (username) ->
  $("#questions").append("<p>" + username + " asked a question</p>")

$(document).ready () ->
  console.log $("form input:text").focus()


  if chatter.page.type == 'moderate'
    socket = io.connect()

    socket.on 'questions', (data) ->
      for i in data.questions
        print_question i

    socket.on 'question', (data) ->
      print_question data.question

    socket.on 'event_start_user_typing', (data) ->
      add_typing_user data.user

    socket.on 'event_end_user_typing', (data) ->
      remove_typing_user data.user

    socket.emit 'get_questions', {topic_id: chatter.page.topic_id}

    socket.emit 'moderate_topic', {topic_id: chatter.page.topic_id}

  else if chatter.page.type == 'join'
    socket = io.connect()

    socket.on 'question_by_user', (data) ->
      flash_username username, "submitted a question."

    # Tell server when user is typing.
    user_typing = False
    timeout_id = null

    $("#create-topic").on "keypress", (event) ->

      # Unregister the end_typing callback.
      window.clearTimeout timeout_id

      # Don't send the event on every keypress, so keep 
      # track of if user is typing.
      if user_typing == False
        user_typing = True
        socket.emit "event_user_start_typing", username: chatter.page.username

      # Register the callback.
      callback = () ->
        user_typing = False
        socket.emit "event_user_end_typing", username: chatter.page.username
      timeout_id = setTimeout callback, 1000
