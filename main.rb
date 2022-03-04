require 'uri'
require 'net/http'
require 'json'
require 'telegram/bot'

BOT_TOKEN = ''
RECEIVER_CHAT_IDS = []
ADMIN_CHAT_ID = ""

def log(msg)
  File.write('bot.log', "#{Time.now}: #{msg}\n", mode: 'a')
  puts msg
end

def listen_messages
  Telegram::Bot::Client.run(BOT_TOKEN) do |bot|
    bot.listen do |message|
      bot.api.send_message(chat_id: message.chat.id, text: "Your chat id is:")
      bot.api.send_message(chat_id: message.chat.id, text: "#{message.chat.id}")
      File.write('chats.log', "#{message.chat.id}\n", mode: 'a')
    end
  end
rescue => e
  send_admin_message("Listen messages error: #{e}")
end

def send_message(msg)
  ::Telegram::Bot::Client.run(BOT_TOKEN) do |bot|
    RECEIVER_CHAT_IDS.each do |chat_id|
      begin
        bot.api.send_message(chat_id: chat_id, text: msg)
        log "Sent message to #{chat_id}"
      rescue => e
        send_admin_message("Send message to #{chat_id} error: #{e}")
      end
    end
  end
end

def send_admin_message(msg)
  ::Telegram::Bot::Client.run(BOT_TOKEN) do |bot|
    bot.api.send_message(chat_id: ADMIN_CHAT_ID, text: msg)
    log "Sent message to admin"
  end
end

def life_check
  while true
    send_admin_message("Bot is alive")

    sleep 15 * 60
  end
end

log "Starting bot"

Thread.new do
  listen_messages
end

Thread.new do
  life_check
end

url = URI.parse('https://api.tinkoff.ru/geo/withdraw/clusters')
req = Net::HTTP::Post.new(url.request_uri, 'Content-Type' => 'application/json')
req.body = '{"bounds":{"bottomLeft":{"lat":53.1647639902733,"lng":50.00488993079199},"topRight":{"lat":53.28261949814105,"lng":50.42683359534278}},"filters":{"banks":["tcs"],"showUnavailable":true,"currencies":["USD"]},"zoom":12}'
http = Net::HTTP.new(url.host, url.port)
http.use_ssl = (url.scheme == "https")

sent_atms = {}

while true
  begin
    found_atms = {}

    if RECEIVER_CHAT_IDS.empty?
      log "Add chat ids"
      sleep 10
    end

    response = http.request(req)

    body = JSON.parse(response.body)

    if body["payload"]["clusters"].length > 0

      body["payload"]["clusters"].each do |cluster|
        cluster["points"].each do |point|
          limits = point["limits"]
          point_id = point["id"]
          address = point["fullAddress"] || point["address"]

          usd_limits = limits.detect { |l| l["currency"] == 'USD' }

          msg = "ATM with $#{usd_limits["amount"]} is available at #{address}!"

          log msg

          unless sent_atms[point_id]
            send_message(msg)
            sent_atms[point_id] = true
          end

          found_atms[point_id] = true
        end
      end

    else
      log "#{Time.now}: no ATMs"
    end

    # clean non actual atms
    sent_atms.keys.each do |atm_id|
      sent_atms.delete(atm_id) unless found_atms[atm_id]
    end
  rescue => e
    send_admin_message(e)
  end

  sleep 10
end
