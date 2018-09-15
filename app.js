// Blog Post Previewer 

// const title = "My First Blog Post";
// const content = "This is my first post!";

  $('#flashMessage')
  .hide()

$('#previewButton').click(function(){
  const title = $('#blogTitleInput').val();
  const content = $('#blogContentInput').val();
  
  $('#blogTitlePreview').text(title);
  $('#blogContentPreview').text(content);
  
  $('#flashMessage')
  .slideDown(1000)
  .delay(3000)
  .slideUp();

});
