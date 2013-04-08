add_typing_user = (username) ->
  $("#users-typing").append("<p><span>" + username + "</span> is typing...</p>")

remove_typing_user = (username) ->
  $("#users-typing span").each (index) ->
    if $(this).text() == username
      $(this).closest("p").remove()

add_question = (question) ->
  $("#questions").prepend("<p>" + question.creator + ": " + question.text + "</p>")

$(document).ready () ->
  $("form input:text").eq(0).focus()

  if chatter.page.type == 'moderate'
    socket = io.connect()

    socket.on 'questions', (data) ->
      for i in data.questions
        add_question i

    socket.on 'question', (data) ->
      add_question data.question

    socket.on 'event_start_user_typing', (data) ->
      add_typing_user data.username

    socket.on 'event_end_user_typing', (data) ->
      remove_typing_user data.username

    socket.on 'connect', () ->
      socket.emit 'get_questions', {topic_id: chatter.page.topic_id}
      socket.emit 'moderate_topic', {topic_id: chatter.page.topic_id}

  else if chatter.page.type == 'watch'
    socket = io.connect()

    # Tell server when user is typing.
    user_typing = false
    timeout_id = null

    $("#new-question").on "keypress", (event) ->

      # Unregister the end_typing callback.
      window.clearTimeout timeout_id

      # Don't send the event on every keypress, so keep track of if user is typing.
      if user_typing == false
        user_typing = true
        socket.emit "event_start_user_typing", username: chatter.page.username, topic_id: chatter.page.topic_id

      # Register the callback.
      callback = () ->
        user_typing = false
        socket.emit "event_end_user_typing", username: chatter.page.username, topic_id: chatter.page.topic_id
      timeout_id = setTimeout callback, 2000

    $("#new-question").closest("form").on "submit", (event) ->
      event.preventDefault()
      $form = $(this)
      $.post "/submit-question", $(this).serialize(), (data) ->
        $("#notice").text("Question submitted successfully")
        $form.find("input[type=text], textarea").val("")
        socket.emit "event_end_user_typing", username: chatter.page.username, topic_id: chatter.page.topic_id

        cb = () ->
          $("#notice").text("")
        setTimeout cb, 2000
