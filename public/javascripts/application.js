// Place your application-specific JavaScript functions and classes here
// This file is automatically included by javascript_include_tag :defaults
$(document).ready(function() {
	$('#click-for-punchline, #question').click(enable_joke_stuff);
	$('#question-mark').click(function(){$("#why").dialog({modal: true, title: "Why login with Twitter or Facebook?", width: 450});})
});

function enable_joke_stuff()
{
	$('#click-for-punchline').hide();
	$('#answer').slideDown('fast');
	$('#question').css('cursor', 'default');
	$("#share").delay(750).slideDown('fast');
	$('#refresh-joke').delay(750).slideDown('fast');	
	origSrcUp = $('#up_arrow').attr("src");
	origSrcDown = $('#down_arrow').attr("src");
	$('#up_arrow').hover(function(){$(this).attr("src","/images/arrow_up.png")}, function(){$(this).attr("src", origSrcUp)});
	$('#down_arrow').hover(function(){$(this).attr("src","/images/arrow_down.png")}, function(){$(this).attr("src", origSrcDown)});
}