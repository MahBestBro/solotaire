package main

import "core:fmt"
import "core:math/rand"
import sa "core:container/small_array"
import "core:slice"

import rl "vendor:raylib"

NUM_DEPOTS :: 7
STARTING_TOTAL_CARDS_IN_DEPOTS :: NUM_DEPOTS * (NUM_DEPOTS + 1) / 2 
MAX_CARDS_IN_DECK :: 52 - STARTING_TOTAL_CARDS_IN_DEPOTS 

SCREEN_WIDTH  :: 1600
SCREEN_HEIGHT :: 900

//NOTE: These include the shadow around the borders 
CARD_TEXTURE_START_OFFSET :: rl.Vector2{8, 13}
CARD_TEXTURE_X_GAP :: 13
CARD_TEXTURE_Y_GAP :: 20
CARD_TEXTURE_CARD_DIMS :: rl.Vector2{109, 149}

//TODO: Better name
BANNER_PAD :: 5
BANNER_HEIGHT :: CARD_TEXTURE_CARD_DIMS.y + 2 * BANNER_PAD
DECK_OFFSET :: rl.Vector2{BANNER_PAD, BANNER_PAD}
DEPOTS_START :: rl.Vector2{20.0, 20.0 + BANNER_HEIGHT}
DEPOT_X_OFFSET := (SCREEN_WIDTH - 2 * DEPOTS_START.x) / NUM_DEPOTS
//The offset from the top of the card required in order to not hide the suit and number
CARD_STACKED_Y_OFFSET :: 45.0 

//TODO: Convert into enum?
ACE :: 1
JACK :: 11
QUEEN :: 12
KING :: 13

Suit :: enum {
    DIAMOND,
    HEART,
    CLUB,
    SPADE
}

//NOTE: This is based off which row the suits are in the sprite sheet
//TODO: Rename
suit_to_int :: proc(suit: Suit) -> (result: int) {
    switch (suit) {
    case .DIAMOND: result = 0 
    case .HEART:   result = 1 
    case .CLUB:    result = 2 
    case .SPADE:   result = 3 
    }
    return
}

same_colour :: proc(suit1: Suit, suit2: Suit) -> bool {
    both_red := (suit1 == .DIAMOND && suit2 == .HEART) || (suit1 == .HEART && suit2 == .DIAMOND)
    both_black := (suit1 == .CLUB && suit2 == .SPADE) || (suit1 == .SPADE && suit2 == .CLUB)
    return both_red || both_black
}

Card :: struct {
    suit: Suit,
    num: int,

    z_index: int,
    face_down: bool,
    rect: rl.Rectangle //TODO: Just have pos? Or take out of struct and calculate instead
}

suit_num_to_card_index :: proc(suit: Suit, num: int) -> int {
    assert(num >= ACE && num <= KING)

    return suit_to_int(suit) * KING + (num - 1)
}

Depot :: sa.Small_Array(20, int)

Deck :: sa.Small_Array(MAX_CARDS_IN_DECK, int)


rect_v :: proc(pos: rl.Vector2, dims: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{pos.x, pos.y, dims.x, dims.y}
}

rect_pos :: proc(rect: rl.Rectangle) -> rl.Vector2 {
    return rl.Vector2{rect.x, rect.y}
}

move_rect :: proc(rect: rl.Rectangle, delta: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{rect.x + delta.x, rect.y + delta.y, rect.width, rect.height}
}

card_texture_rect :: proc(suit: Suit, num: int, face_down: bool) -> (tex_rect: rl.Rectangle) {
    assert(num >= ACE && num <= KING)
    
    if face_down {
        tex_rect = rect_v(rl.Vector2{}, CARD_TEXTURE_CARD_DIMS)
        return
    }

    row := f32(suit_to_int(suit))
    column := f32(num - 1)

    offset := rl.Vector2{
        CARD_TEXTURE_CARD_DIMS.x + CARD_TEXTURE_X_GAP, 
        CARD_TEXTURE_CARD_DIMS.y + CARD_TEXTURE_Y_GAP
    }

    tex_rect = rect_v(CARD_TEXTURE_START_OFFSET, CARD_TEXTURE_CARD_DIMS)
    tex_rect = move_rect(tex_rect, rl.Vector2{column * offset.x, row * offset.y})
    return
}

initialise_game :: proc(cards: ^[52]Card) -> (depots: [NUM_DEPOTS]Depot, deck: Deck) {
    initial_shuffled_card_indices : [52]int
    for &card, i in initial_shuffled_card_indices do card = i
    rand.shuffle(initial_shuffled_card_indices[:])

    //Set up depots
    for depot_max in 1..=NUM_DEPOTS {
        depot_index := depot_max - 1
        for y in 0..<depot_max {
            //NOTE: The first part is the sum of all previous cards using the formula for consecutive sum from 1..n
            i := (depot_max - 1) * depot_max / 2 + y
            card_index := initial_shuffled_card_indices[i]
            
            sa.append(&depots[depot_index], card_index)
            
            cards^[card_index].face_down = y < depot_max - 1
        }
    }

    //Set up deck
    for i in STARTING_TOTAL_CARDS_IN_DEPOTS..<52 {
        card_index := initial_shuffled_card_indices[i]
        
        sa.append(&deck, card_index)

        cards[card_index].face_down = true
        cards[card_index].z_index = i
    }

    return
}

depot_index_from_card_index :: proc(depots: ^[NUM_DEPOTS]Depot, card_index: int) -> Maybe(int) {
    for &depot, depot_index in depots {
        if slice.contains(sa.slice(&depot), card_index) do return depot_index
    }
    return nil
}

DepotLocation :: struct {
    depot_index: int,
    index_in_depot: int
}

DeckLocation :: int

CardLocation :: union {
    DepotLocation,
    DeckLocation
}

card_index_location :: proc(depots: ^[NUM_DEPOTS]Depot, deck: ^Deck, target_card_index: int) -> CardLocation {
    for &depot, depot_index in depots {
        for card_index, index_in_depot in sa.slice(&depot) {
            if card_index == target_card_index {
                return DepotLocation{ depot_index = depot_index, index_in_depot = index_in_depot }
            }
        }
    }

    for card_index, index_in_deck in sa.slice(deck) {
        if card_index == target_card_index do return index_in_deck
    }

    assert(false) //NOTE: This should be unreachable, is reached likely means target_card_index is invalid
    return -1
}

main :: proc() {

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "solotaire")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    cards : [52]Card
    for suit, y in Suit {
        for num in ACE..=KING {
            x := num - 1
            
            card_index := y * KING + x
            
            cards[card_index].suit = suit
            cards[card_index].num = num
            cards[card_index].face_down = false
        }
    }

    depots, deck := initialise_game(&cards) 
    
    /*
    first_card_loc := card_index_location(&depots, &deck, suit_num_to_card_index(.DIAMOND, 2))
    old_first_depot_card_index := sa.get(depots[0], 0)
    sa.set(&depots[0], 0, suit_num_to_card_index(.DIAMOND, 2))
    cards[suit_num_to_card_index(.DIAMOND, 2)].face_down = false
    switch loc in first_card_loc {
    case DepotLocation: 
        sa.set(&depots[loc.depot_index], loc.index_in_depot, old_first_depot_card_index)
    
    case DeckLocation: 
        sa.set(&deck, loc, old_first_depot_card_index)
    }
    
    second_card_loc := card_index_location(&depots, &deck, suit_num_to_card_index(.CLUB, 3))
    old_second_depot_card_index := sa.get(depots[1], 1)
    sa.set(&depots[1], 1, suit_num_to_card_index(.CLUB, 3))
    cards[suit_num_to_card_index(.CLUB, 3)].face_down = false
    switch loc in second_card_loc {
    case DepotLocation: 
        sa.set(&depots[loc.depot_index], loc.index_in_depot, old_second_depot_card_index)
    
    case DeckLocation: 
        sa.set(&deck, loc, old_second_depot_card_index)
    }
    
    third_card_loc := card_index_location(&depots, &deck, suit_num_to_card_index(.DIAMOND, KING))
    old_third_depot_card_index := sa.get(depots[2], 2)
    sa.set(&depots[2], 2, suit_num_to_card_index(.DIAMOND, KING))
    cards[suit_num_to_card_index(.DIAMOND, KING)].face_down = false
    switch loc in third_card_loc {
    case DepotLocation: 
        sa.set(&depots[loc.depot_index], loc.index_in_depot, old_third_depot_card_index)
    
    case DeckLocation: 
        sa.set(&deck, loc, old_third_depot_card_index)
    }
    */

    all_cards_texture := rl.LoadTexture("assets/all_cards.png")
    card_back_texture := rl.LoadTexture("assets/card_back.png")

    selected_card_index: Maybe(int)
    mouse_pos_on_click: rl.Vector2
    card_pos_on_click: rl.Vector2
    //TODO: Make something more descriptive than Maybe type?
    original_depot_index: Maybe(int) //nil means it came from the deck

    for !rl.WindowShouldClose() {
        
        mouse_pos := rl.GetMousePosition()

        if rl.IsMouseButtonPressed(.LEFT) {
            
            potential_selected_indices : sa.Small_Array(52, int)
            for card, i in cards {
                if !card.face_down && rl.CheckCollisionPointRec(mouse_pos, card.rect) {
                    sa.append(&potential_selected_indices, i)
                }
            }

            if sa.len(potential_selected_indices) > 0 {
                selected_index := sa.get(potential_selected_indices, 0)
                for i in sa.slice(&potential_selected_indices)[1:] {
                    if cards[i].z_index > cards[selected_index].z_index {
                        selected_index = i
                    }
                }

                selected_card_index = selected_index
                mouse_pos_on_click = mouse_pos
                card_pos_on_click = rect_pos(cards[selected_index].rect)
                original_depot_index = depot_index_from_card_index(&depots, selected_index)
            }
        }

        if card_index, ok := selected_card_index.?; ok && rl.IsMouseButtonReleased(.LEFT) {
                
            //TODO: Consider just going to nearest depot instead of checking for intersection?
            original_depot_index_index, selected_card_not_from_deck := original_depot_index.?
            for depot_index in 0..<len(depots) {
                if selected_card_not_from_deck && original_depot_index_index == depot_index do continue
                
                depot_min_x := DEPOTS_START.x + DEPOT_X_OFFSET * f32(depot_index)
                depot_max_x := depot_min_x + CARD_TEXTURE_CARD_DIMS.x
                selected_card_min_x := cards[card_index].rect.x
                selected_card_max_x := cards[card_index].rect.x + cards[card_index].rect.width
                
                card_min_x_in_depot := selected_card_min_x >= depot_min_x && selected_card_min_x <= depot_max_x
                card_max_x_in_depot := selected_card_max_x >= depot_min_x && selected_card_max_x <= depot_max_x
                if card_min_x_in_depot || card_max_x_in_depot {
                    cards_differ_in_colour := false 
                    top_is_one_more := false

                    depot_len := sa.len(depots[depot_index])
                    if depot_len > 0 {
                        top_card_in_depot := cards[sa.get(depots[depot_index], depot_len - 1)]
                        cards_differ_in_colour = !same_colour(top_card_in_depot.suit, cards[card_index].suit)
                        top_is_one_more = top_card_in_depot.num - cards[card_index].num == 1
                    }
                    
                    moving_king_to_empty_depot := cards[card_index].num == KING && depot_len == 0

                    if (cards_differ_in_colour && top_is_one_more) || moving_king_to_empty_depot {
                        sa.append(&depots[depot_index], card_index)
                        sa.pop_back(&depots[original_depot_index_index])
                    }
                    
                    break
                }
            }
            
            selected_card_index = nil
        }

        if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.R) {
            depots, deck = initialise_game(&cards)
        }

        for &depot, depot_index in depots {
            for card_index, y in sa.slice(&depot) {
                card_offset := rl.Vector2{DEPOT_X_OFFSET * f32(depot_index), CARD_STACKED_Y_OFFSET * f32(y)}
                card_pos := DEPOTS_START + card_offset
                
                cards[card_index].rect = rect_v(card_pos, CARD_TEXTURE_CARD_DIMS)
                cards[card_index].z_index = y
            }

            cards[sa.get(depot, sa.len(depot) - 1)].face_down = false
        }

        for card_index in sa.slice(&deck) {
            cards[card_index].rect = rect_v(DECK_OFFSET, CARD_TEXTURE_CARD_DIMS)
        }

        if card_index, ok := selected_card_index.?; ok {
            held_card_pos := card_pos_on_click + (mouse_pos - mouse_pos_on_click)
            cards[card_index].rect.x = held_card_pos.x 
            cards[card_index].rect.y = held_card_pos.y 
        }

        
        {
            rl.BeginDrawing()
            defer rl.EndDrawing()

            rl.ClearBackground(rl.Color{17, 128, 0, 255})

            rl.DrawRectangleV(
                rl.Vector2{},
                rl.Vector2{SCREEN_WIDTH, BANNER_HEIGHT}, rl.Color{12, 87, 0, 255}
            )

            cards_to_draw := slice.clone(cards[:], context.temp_allocator)

            compare_by_z_index :: proc (i, j: Card) -> bool { return i.z_index < j.z_index }
            slice.sort_by(cards_to_draw, compare_by_z_index)

            for card in cards_to_draw {
                rl.DrawTextureRec(
                    all_cards_texture if !card.face_down else card_back_texture, 
                    card_texture_rect(card.suit, card.num, card.face_down), 
                    rect_pos(card.rect), 
                    rl.WHITE
                )
            }

            //rl.DrawFPS(10, 10)
        }
    }
}