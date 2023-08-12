require "json"

class Dataset
  def load!
    file = File.read("latest.json")
    data = JSON.parse(file)

    data.map! { Entry.new(_1) }.compact!
    @pokemon, data = data.partition { _1.is_a? Entry::PokemonTemplate }
    @level_settings, data = data.partition { _1.is_a? Entry::LevelSettings }
    throw "more than one level_settings entry" if @level_settings.length > 1
    @level_settings = @level_settings.first

    self
  end

  attr_reader :level_settings, :pokemon

  def pokemon_by_id = @pokemon_by_id ||= @pokemon.map { |p| [p.id, p] }.to_h
end

class Entry
  def self.new(raw)
    obj = nil
    if raw["data"].key? "pokemonSettings"
      obj = PokemonTemplate.allocate
    elsif raw["templateId"] == "PLAYER_LEVEL_SETTINGS"
      obj = LevelSettings.allocate
    else
      #throw 'Unknown entry type', raw
    end
    return unless obj
    obj.send(:initialize, raw["data"])

    obj # or throw 'Unknown entry type', raw
  end

  def initialize(id, data)
    @template_id = id
    @data = data
  end

  def template_id
    @template_id
  end
end

class Entry::LevelSettings < Entry
  def initialize(raw)
    super(raw["templateId"], raw["playerLevel"])
  end

  def cp_multiplier
    @cp_multiplier ||= [nil, *@data["cpMultiplier"]]
  end
end

class Entry::PokemonTemplate < Entry
  def initialize(raw)
    super(raw["templateId"], raw["pokemonSettings"])
  end

  def id
    @id ||= @data["pokemonId"]
  end

  def base_stamina
    @base_stamina ||= @data["stats"]["baseStamina"]
  end

  def base_attack
    @base_attack ||= @data["stats"]["baseAttack"]
  end

  def base_defense
    @base_defense ||= @data["stats"]["baseDefense"]
  end
end

class Pokemon
  def initialize(template, data, level_settings)
    @template = template
    @data = data
    @level_settings = level_settings
  end

  attr_reader :template, :data, :level_settings

  def base_attack = @base_attack ||= template.base_attack
  def base_defense = @base_defense ||= template.base_defense
  def base_stamina = @base_stamina ||= template.base_stamina

  def attack = @attack ||= base_attack + attack_iv
  def defense = @defense ||= base_defense + defense_iv
  def stamina = @stamina ||= base_stamina + stamina_iv

  def attack_iv = @attack_iv ||= @data["attack_iv"]
  def defense_iv = @defense_iv ||= @data["defense_iv"]
  def stamina_iv = @stamina_iv ||= @data["hp_iv"]

  def level = @level ||= @data["level"]

  def cpm
    @cpm ||= begin
        if level != level.floor
          (level_settings.cp_multiplier[level.floor] + level_settings.cp_multiplier[level.floor + 1]) / 2.0
        else
          level_settings.cp_multiplier[level]
        end
      end
  end

  def cp
    @cp ||= begin
        x = 1.0
        x *= attack
        x *= Math.sqrt(defense * stamina)
        x *= cpm
        x *= cpm
        x /= 10.0
        x.floor
      end
  end
end

class Roster
  def initialize(ds)
    @ds = ds
    @pokemon = []
  end

  attr_reader :ds, :pokemon

  def load!(filename)
    @pokemon = JSON.parse(File.read(filename)).map do |p|
      template = ds.pokemon_by_id[p["id"]] or throw "Unknown pokemon id #{p["id"]}"
      Pokemon.new(template, p, ds.level_settings)
    end
  end

  def save!(filename)
    File.write(filename, JSON.pretty_generate(@pokemon.map do |p|
      {
        "id" => p.template.id,
        "attack_iv" => p.attack_iv,
        "defense_iv" => p.defense_iv,
        "hp_iv" => p.stamina_iv,
        "level" => p.level,
      }
    end))
  end

  def add(id:, ivs:, cp:)
    template = ds.pokemon_by_id[id] or throw "Unknown pokemon id #{id}"

    attack_iv, defense_iv, hp_iv = ivs

    level_min = 1
    level_max = 55

    while level_min < level_max
      level_guess = (level_min + level_max) / 2.0
      level_guess = (level_guess * 2).floor / 2.0
      pokemon = Pokemon.new(template, {
        "attack_iv" => attack_iv,
        "defense_iv" => defense_iv,
        "hp_iv" => hp_iv,
        "level" => level_guess,
      }, ds.level_settings)

      if pokemon.cp < cp
        level_min = level_guess + 0.5
      elsif pokemon.cp > cp
        level_max = level_guess
      else
        level_min = level_max = level_guess
      end
    end

    if pokemon.cp != cp
      puts "Failed to find level for #{id} with #{ivs} and cp #{cp}, closest was #{pokemon.level} with cp #{pokemon.cp}"
      throw "Failed to find level for #{id} with #{ivs} and cp #{cp}"
    end

    @pokemon << pokemon
  end
end

ds = Dataset.new.load!
r = Roster.new(ds)

r.load! "roster.json"
r.add(
  id: "TORTERRA",
  ivs: [11,7,11],
  cp: 2199,
)
r.save! "roster.json"
