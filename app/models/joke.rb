# encoding: utf-8

class Joke < ActiveRecord::Base
  make_voteable

  has_many :categories
  has_many :favorite_jokes, :dependent => :destroy
  has_many :alternate_punchlines
  
  belongs_to :user
  
  validates_presence_of :question, :answer
  
  attr_reader :auto_post
  attr_writer :auto_post

  after_create :generate_bitly_url

  def favorite_count
    self.favorite_jokes.count
  end

  def fork_count
    self.alternate_punchlines.count
  end
  
  def self.jokeler_update
    require 'rss/2.0'
    # scan the jokeler's RSS for new jokeler posts and associate them with jokes
    source = "http://jokeler.tumblr.com/rss"
    content = ""
    open(source) do |s| content = s.read end
    rss = RSS::Parser.parse(content, false)
    rss = rss.items.delete_if{|x| !x.title.starts_with? "http://"}
    rss.each do |x| 
      id = x.title.split('/').last
      joke = Joke.find(id)
      if !joke.jokeler_url
        joke.jokeler_url = x.link      
        joke.save!
      end
    end
  end
  
  # add bitly urls to jokes that don't have them (more of a fixerupper)
  # limit to 10 by default so we don't overload bit.ly API request limits
  def self.add_bitly_urls(count = 10)
    Joke.where(:bitly_url => nil).limit(count).each do |joke|
      joke.generate_bitly_url
    end
  end
  
  def generate_bitly_url
    bitly = Bitly.client
    response = bitly.shorten("http://jokels.com/jokes/#{self.id}")
    self.bitly_url = response.short_url
    self.save!
  end

  def sms_joke to
    config = YAML.load_file("#{RAILS_ROOT}/config/application.yml")[RAILS_ENV]
    account_sid = config["twilio"]["account_sid"]
    auth_token = config["twilio"]["auth_token"]
    from = config["twilio"]["from"]
    body = "Q: #{self.question} A: #{self.answer} - jokels.com"
    if body.length > 160
      body = "Q: #{self.question} A: #{self.bitly_url}"
      if body.length > 160
        body = "Someone sent you a joke from Jokels.com! It's too long for SMS. View online at #{self.bitly_url}"
      end
    end

    twilio = Twilio::REST::Client.new account_sid, auth_token
    twilio.account.sms.messages.create(:from => from,:to => to,:body => body)
  end
  
  # tweet yetserday's top joke
  # this method is more disgusting than I imagined
  def self.post_top_joke
     # Time.now - 1.day makes me feel like I'm using a language made for six year olds
     top_joke = Joke.where(['created_at BETWEEN ? AND ? AND (up_votes - down_votes) >= -2 ', Time.now-1.day-2.hour, Time.now-2.hour]).sort_by{|x| x.votes}.reverse[0]
     # only tweet if there is a top joke from yesterday
     if top_joke
       # generate bitly url if it hasn't been generated yet (probably not an issue)
       if top_joke.bitly_url.nil?
         top_joke.generate_bitly_url
       end
       
       # Format: Jan 01 top joke: joke's question - http://jkls.co/url
       tweet = "#{Date.yesterday.strftime("%b %d")} top joke: #{top_joke.question} - #{top_joke.bitly_url}"
       
       jokels_user = User.find 1 # @jokelscom
       client = Twitter::Client.new(:oauth_token => jokels_user.token, :oauth_token_secret => jokels_user.secret)
       
       settings = YAML.load_file("#{RAILS_ROOT}/config/application.yml")[RAILS_ENV]
       
       user = top_joke.user
       fb_post = tweet
       if user && user.provider == "twitter"
         twitter_name = "@"+user.name
         
         # Format: Jan 01 top joke: joke's question - http://jkls.co/url by @twittername
         tweet_with_author = "#{tweet} by #{twitter_name}" 
         fb_post = fb_post + " by Twitter User #{twitter_name}"
         
         if tweet_with_author.length <= 140
           client.update(tweet_with_author)
         else
           # turncate the joke's question, we want the author to be shown every time
           # formula:
           # 140 = max tweet length
           # 45 = the number of characters for date, 'top joke', bit.ly url, dash, and 'by' 
           # twitter_name.length = the characters for the twitter handle with the @
           # 1 = room for elipsis character
           # whatever's left is how long our question can be in the tweet
           question_length = 140-45-twitter_name.length-1
           
           # Format: Jan 01 top joke: joke's questi… - http://jkls.co/url by @twittername
           tweet_with_author = "#{Date.yesterday.strftime("%b %d")} top joke: #{top_joke.question[0..question_length]}… - #{top_joke.bitly_url} by #{twitter_name}"
           client.update(tweet_with_author)
         end
       elsif tweet.length <= 140
         client.update(tweet)
       else
         # we should have 98 characters for the question
         # Format: Jan 01 top joke: joke's questi… - http://jkls.co/url
         tweet = "#{Date.yesterday.strftime("%b %d")} top joke: #{top_joke.question[0..98]}… - #{top_joke.bitly_url}"
         client.update(tweet)
       end     

        FGraph.publish_feed('me', :message => fb_post, :access_token => settings["facebook"]["page_access_token"])
     end
   end
   
   def self.random_joke
     result_joke = nil
     
     while result_joke.nil?
      rand_id = rand(Joke.count)
      result_joke = Joke.first(:conditions => [ "id >= ? and (up_votes - down_votes) >= -2", rand_id])
     end
     
     result_joke
   end

   def self.find_joke_that_fits(limit=140, threshold=1)
     logger.debug "test"
     count = Joke.count(:conditions => "(length(question) + length(answer)) < #{limit-1} and (up_votes - down_votes) >= #{threshold}")
     offset = rand(count)
     random_joke = (Joke.where("(length(question) + length(answer)) < #{limit-1} and (up_votes - down_votes) >= #{threshold}").limit(1).offset(offset))[0]
   end

   def self.search_twitter_users
      bot = Chatterbot::Bot.new
      jokels_user = User.find 1 # @jokelscom
      client = Twitter::Client.new(:oauth_token => jokels_user.token, :oauth_token_secret => jokels_user.secret)

      bot.search("\"tell me a joke\"") do |tweet|
        # exclude any tweets which are directed @ someone
        if tweet[:to_user].nil?
          user_in_need = tweet[:from_user]
          user_length = user_in_need.length
          reply_joke = Joke.find_joke_that_fits(140 - (user_length+2))

          client.update "@#{user_in_need} #{reply_joke.question} #{reply_joke.answer}", :in_reply_to_status_id => tweet[:id] 
        end
      end

      bot.search("\"tell me another\" to:jokelscom") do |tweet|
        user_in_need = tweet[:from_user]
        user_length = user_in_need.length
        reply_joke = Joke.find_joke_that_fits(140 - (user_length+2))

        client.update "@#{user_in_need} #{reply_joke.question} #{reply_joke.answer}", :in_reply_to_status_id => tweet[:id] 
      end

      # Jacquie gave me this idea.  People are polite, we should be too.
      bot.search("\"thank you\" OR thanks to:jokelscom") do |tweet|
        polite_user = tweet[:from_user]

        client.update "@#{polite_user} You're welcome! Anytime!", :in_reply_to_status_id => tweet[:id] 
      end

      # so many people don't get our jokels! Luckily, neither do we
      bot.search("\"I don't get it\" OR \"I dont get it\" TO:jokelscom") do |tweet|
        confused_user = tweet[:from_user]

        client.update "@#{confused_user} Neither do we.", :in_reply_to_status_id => tweet[:id] 
      end

    bot.update_config
   end
end
