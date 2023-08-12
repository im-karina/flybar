require 'net/http'

uri = URI('https://raw.githubusercontent.com/PokeMiners/game_masters/master/latest/latest.json')
response = Net::HTTP.get_response(uri)
File.write("latest.json", response.body.to_s)
puts "Downloaded latest.json"
