//
//  SearchValues.swift
//  Hayase
//
//  Created by scigward.
//

import Foundation

enum SearchFilterOptionGroup: Hashable {
    case genre
    case tag
    case plain
}

struct SearchFilterOption: Hashable {
    let value: String
    let label: String
    let group: SearchFilterOptionGroup

    init(value: String, label: String? = nil, group: SearchFilterOptionGroup = .plain) {
        self.value = value
        self.label = label ?? value
        self.group = group
    }
}

enum SearchFilterType: Int, CaseIterable {
    case genres
    case year
    case season
    case format
    case status
    case sort
    case onList
    case trace

    var label: String {
        switch self {
        case .genres: return "Genres"
        case .year: return "Year"
        case .season: return "Season"
        case .format: return "Formats"
        case .status: return "Status"
        case .sort: return "Sort"
        case .onList: return "My List"
        case .trace: return "IDs"
        }
    }

    var isMultiSelect: Bool {
        switch self {
        case .genres, .format, .status: return true
        default: return false
        }
    }

    var placeholder: String {
        self == .sort ? "Accuracy" : "Any"
    }
}

enum SearchValues {
    static let genres: [SearchFilterOption] = [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Hentai", "Horror",
        "Mahou Shoujo", "Mecha", "Music", "Mystery", "Psychological", "Romance", "Sci-Fi",
        "Slice of Life", "Sports", "Supernatural", "Thriller",
    ].map { SearchFilterOption(value: $0, group: .genre) }

    static let genreSet = Set(genres.map(\.value))

    static var years: [SearchFilterOption] {
        let current = Calendar.current.component(.year, from: Date())
        return (0...(current - 1940 + 1)).map { index in
            let year = String(current + 2 - index)
            return SearchFilterOption(value: year)
        }
    }

    static let seasons: [SearchFilterOption] = [
        SearchFilterOption(value: "SPRING", label: "Spring"),
        SearchFilterOption(value: "SUMMER", label: "Summer"),
        SearchFilterOption(value: "FALL", label: "Fall"),
        SearchFilterOption(value: "WINTER", label: "Winter"),
    ]

    static let formats: [SearchFilterOption] = [
        SearchFilterOption(value: "TV", label: "TV Show"),
        SearchFilterOption(value: "MOVIE", label: "Movie"),
        SearchFilterOption(value: "TV_SHORT", label: "TV Short"),
        SearchFilterOption(value: "OVA"),
        SearchFilterOption(value: "ONA"),
    ]

    static let statuses: [SearchFilterOption] = [
        SearchFilterOption(value: "RELEASING", label: "Airing"),
        SearchFilterOption(value: "FINISHED", label: "Finished"),
        SearchFilterOption(value: "NOT_YET_RELEASED", label: "Not Yet Aired"),
        SearchFilterOption(value: "CANCELLED", label: "Cancelled"),
    ]

    static let sorts: [SearchFilterOption] = [
        SearchFilterOption(value: "TITLE_ROMAJI_DESC", label: "Name"),
        SearchFilterOption(value: "START_DATE_DESC", label: "Release Date"),
        SearchFilterOption(value: "SCORE_DESC", label: "Score"),
        SearchFilterOption(value: "POPULARITY_DESC", label: "Popularity"),
        SearchFilterOption(value: "TRENDING_DESC", label: "Trending"),
        SearchFilterOption(value: "UPDATED_AT_DESC", label: "Updated Date"),
        SearchFilterOption(value: "TITLE_ROMAJI", label: "Name Asc"),
        SearchFilterOption(value: "START_DATE", label: "Release Date Asc"),
        SearchFilterOption(value: "SCORE", label: "Score Asc"),
        SearchFilterOption(value: "POPULARITY", label: "Popularity Asc"),
        SearchFilterOption(value: "TRENDING", label: "Trending Asc"),
        SearchFilterOption(value: "UPDATED_AT", label: "Updated Date Asc"),
    ]

    static let onList: [SearchFilterOption] = [
        SearchFilterOption(value: "true", label: "On List"),
        SearchFilterOption(value: "false", label: "Not On List"),
    ]

    static let tags: [SearchFilterOption] = tagNames.map {
        SearchFilterOption(value: $0, group: .tag)
    }

    static let genresAndTags: [SearchFilterOption] = genres + tags

    static func options(for type: SearchFilterType) -> [SearchFilterOption] {
        switch type {
        case .genres: return genresAndTags
        case .year: return years
        case .season: return seasons
        case .format: return formats
        case .status: return statuses
        case .sort: return sorts
        case .onList: return onList
        case .trace: return []
        }
    }

    static func label(for value: String, in type: SearchFilterType) -> String {
        options(for: type).first { $0.value == value }?.label ?? value
    }

    private static let tagNames = """
4-koma
Achromatic
Achronological Order
Acrobatics
Acting
Adoption
Advertisement
Afterlife
Age Gap
Age Regression
Agender
Agriculture
Airsoft
Alchemy
Aliens
Alternate Universe
American Football
Amnesia
Anachronism
Ancient China
Angels
Animals
Anthology
Anthropomorphism
Anti-Hero
Archery
Aromantic
Arranged Marriage
Artificial Intelligence
Asexual
Assassins
Astronomy
Athletics
Augmented Reality
Autobiographical
Aviation
Badminton
Ballet
Band
Bar
Baseball
Basketball
Battle Royale
Biographical
Bisexual
Blackmail
Board Game
Boarding School
Body Horror
Body Image
Body Swapping
Bowling
Boxing
Boys' Love
Bullying
Butler
Calligraphy
Camping
Cannibalism
Card Battle
Cars
Centaur
CGI
Cheerleading
Chibi
Chimera
Chuunibyou
Circus
Class Struggle
Classic Literature
Classical Music
Clone
Coastal
Cohabitation
College
Coming of Age
Conspiracy
Cosmic Horror
Cosplay
Cowboys
Creature Taming
Crime
Criminal Organization
Crossdressing
Crossover
Cult
Cultivation
Curses
Cute Boys Doing Cute Things
Cute Girls Doing Cute Things
Cyberpunk
Cyborg
Cycling
Dancing
Death Game
Delinquents
Demons
Denpa
Desert
Detective
Dinosaurs
Disability
Dissociative Identities
Dragons
Drawing
Drugs
Dullahan
Dungeon
Dystopian
E-Sports
Eco-Horror
Economics
Educational
Elderly Protagonist
Elf
Ensemble Cast
Environmental
Episodic
Ero Guro
Espionage
Estranged Family
Exorcism
Fairy
Fairy Tale
Fake Relationship
Family Life
Fashion
Female Harem
Female Protagonist
Femboy
Fencing
Filmmaking
Firefighters
Fishing
Fitness
Flash
Food
Football
Foreign
Found Family
Fugitive
Full CGI
Full Color
Gambling
Gangs
Gender Bending
Ghost
Go
Gods
Golf
Gore
Guns
Gyaru
Handball
Henshin
Heterosexual
Hikikomori
Hip-hop Music
Historical
Homeless
Horticulture
Ice Skating
Idol
Indigenous Cultures
Inn
Isekai
Iyashikei
Jazz Music
Josei
Judo
Kabuki
Kaiju
Karuta
Kemonomimi
Kids
Kingdom Management
Konbini
Kuudere
Lacrosse
Language Barrier
LGBTQ+ Themes
Long Strip
Lost Civilization
Love Triangle
Mafia
Magic
Mahjong
Maids
Makeup
Male Harem
Male Protagonist
Manzai
Marriage
Martial Arts
Matchmaking
Matriarchy
Medicine
Medieval
Memory Manipulation
Mermaid
Meta
Metal Music
Military
Mixed Gender Harem
Mixed Media
Modeling
Monster Boy
Monster Girl
Mopeds
Motorcycles
Mountaineering
Musical Theater
Mythology
Natural Disaster
Necromancy
Nekomimi
Ninja
No Dialogue
Noir
Non-fiction
Nudity
Nun
Office
Office Lady
Oiran
Ojou-sama
Orphan
Otaku Culture
Outdoor Activities
Pandemic
Parenthood
Parkour
Parody
Philosophy
Photography
Pirates
Poker
Police
Politics
Polyamorous
Post-Apocalyptic
POV
Pregnancy
Primarily Adult Cast
Primarily Animal Cast
Primarily Child Cast
Primarily Female Cast
Primarily Male Cast
Primarily Teen Cast
Prison
Proxy Battle
Psychosexual
Puppetry
Rakugo
Real Robot
Rehabilitation
Reincarnation
Religion
Rescue
Restaurant
Revenge
Reverse Isekai
Robots
Rock Music
Rotoscoping
Royal Affairs
Rugby
Rural
Samurai
Satire
School
School Club
Scuba Diving
Seinen
Shapeshifting
Ships
Shogi
Shoujo
Shounen
Shrine Maiden
Skateboarding
Skeleton
Slapstick
Slavery
Snowscape
Software Development
Space
Space Opera
Spearplay
Steampunk
Stop Motion
Succubus
Suicide
Sumo
Super Power
Super Robot
Superhero
Surfing
Surreal Comedy
Survival
Swimming
Swordplay
Table Tennis
Tanks
Tanned Skin
Teacher
Teens' Love
Tennis
Terrorism
Time Loop
Time Manipulation
Time Skip
Tokusatsu
Tomboy
Torture
Tragedy
Trains
Transgender
Travel
Triads
Tsundere
Twins
Unrequited Love
Urban
Urban Fantasy
Vampire
Vertical Video
Veterinarian
Video Games
Vikings
Villainess
Virtual World
Vocal Synth
Volleyball
VTuber
War
Werewolf
Wilderness
Witch
Work
Wrestling
Writing
Wuxia
Yakuza
Yandere
Youkai
Yuri
Zombie
"""
        .split(separator: "\n")
        .map(String.init)
}
