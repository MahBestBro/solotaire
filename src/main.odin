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

//TODO: Better name, this is convoluted
RESET_DECK_MARKER_TEXTURE_RECT :: rl.Rectangle{
    x = CARD_TEXTURE_START_OFFSET.x + 4.0 * (CARD_TEXTURE_CARD_DIMS.x + CARD_TEXTURE_X_GAP),
    y = CARD_TEXTURE_START_OFFSET.y + 4.0 * (CARD_TEXTURE_CARD_DIMS.y + CARD_TEXTURE_Y_GAP),
    width = CARD_TEXTURE_CARD_DIMS.x,
    height = CARD_TEXTURE_CARD_DIMS.y
}

//TODO: Better name
BANNER_PAD :: 5
BANNER_HEIGHT :: CARD_TEXTURE_CARD_DIMS.y + 2 * BANNER_PAD
DECK_POS :: rl.Vector2{BANNER_PAD, BANNER_PAD}
DRAW_PILE_START :: rl.Vector2{DECK_POS.x + CARD_TEXTURE_CARD_DIMS.x + 20.0, DECK_POS.y}
SUIT_PILE_START :: rl.Vector2{DRAW_PILE_START.x + (CARD_TEXTURE_CARD_DIMS.x + 20.0) * 2.0, DECK_POS.y}
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
    DIAMOND = 0,
    HEART = 1,
    CLUB = 2,
    SPADE = 3
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

    return int(suit) * KING + (num - 1)
}

card_index_to_suit_num :: proc(card_index: int) -> (suit: Suit, num: int) {
    assert(card_index >= 0 && card_index < 52)

    suit = Suit(card_index / KING)
    num = card_index % KING + ACE
    return 
}

Depot :: sa.Small_Array(20, int)

Deck :: sa.Small_Array(MAX_CARDS_IN_DECK, int)

Board :: struct {
    depots: [NUM_DEPOTS]Depot,
    deck: Deck,
    draw_pile: Deck,
    //NOTE: Each pile just tracks what the top card is since it has to be ordered anyways
    suit_piles: [4]int   
}


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

    row := f32(suit)
    column := f32(num - 1)

    offset := rl.Vector2{
        CARD_TEXTURE_CARD_DIMS.x + CARD_TEXTURE_X_GAP, 
        CARD_TEXTURE_CARD_DIMS.y + CARD_TEXTURE_Y_GAP
    }

    tex_rect = rect_v(CARD_TEXTURE_START_OFFSET, CARD_TEXTURE_CARD_DIMS)
    tex_rect = move_rect(tex_rect, rl.Vector2{column * offset.x, row * offset.y})
    return
}

suit_pile_texture_rect :: proc(suit: Suit) -> rl.Rectangle {
    offset := rl.Vector2{
        (CARD_TEXTURE_CARD_DIMS.x + CARD_TEXTURE_X_GAP) * f32(suit), 
        (CARD_TEXTURE_CARD_DIMS.y + CARD_TEXTURE_Y_GAP) * 4.0
    }
    return rect_v(CARD_TEXTURE_START_OFFSET + offset, CARD_TEXTURE_CARD_DIMS)
} 

suit_pile_pos :: proc(suit: Suit) -> rl.Vector2 {
    return SUIT_PILE_START + rl.Vector2{f32(suit) * (CARD_TEXTURE_CARD_DIMS.x + 20.0), 0.0}
}

//NOTE: We need not do anything for draw_pile since it should just be zero-initialised anyways, which is the 
//starting state we want 
initialise_board :: proc(cards: ^[52]Card) -> (board: Board) {
    initial_shuffled_card_indices : [52]int
    for &card, i in initial_shuffled_card_indices do card = i
    rand.shuffle(initial_shuffled_card_indices[:])

    //Set up depots
    for depot_max in 1..=NUM_DEPOTS {
        depot_index := depot_max - 1
        for y in 0..<depot_max {
            //NOTE: The first part is the sum of all previous cards using the formula for consecutive sum from 
            //1..n
            i := (depot_max - 1) * depot_max / 2 + y
            card_index := initial_shuffled_card_indices[i]
            
            sa.append(&board.depots[depot_index], card_index)
            
            cards^[card_index].face_down = y < depot_max - 1
        }
    }

    //Set up deck
    for i in STARTING_TOTAL_CARDS_IN_DEPOTS..<52 {
        card_index := initial_shuffled_card_indices[i]
        
        sa.append(&board.deck, card_index)

        cards[card_index].face_down = true
        cards[card_index].z_index = i
    }

    return
}

DepotLocation :: struct {
    depot_index: int,
    index_in_depot: int
}

DeckLocation :: distinct int
DrawPileLocation :: distinct int
SuitPileLocation :: Suit

CardLocation :: union {
    DepotLocation,
    DeckLocation,
    DrawPileLocation,
    SuitPileLocation
}

card_index_location :: proc(board: ^Board, target_card_index: int) -> CardLocation {
    for &depot, depot_index in board.depots {
        for card_index, index_in_depot in sa.slice(&depot) {
            if card_index == target_card_index {
                return DepotLocation{ depot_index = depot_index, index_in_depot = index_in_depot }
            }
        }
    }

    for card_index, index_in_deck in sa.slice(&board.deck) {
        if card_index == target_card_index do return DeckLocation(card_index)
    }

    for card_index, index_in_deck in sa.slice(&board.draw_pile) {
        if card_index == target_card_index do return DrawPileLocation(card_index)
    }

    suit, num := card_index_to_suit_num(target_card_index)
    if board.suit_piles[int(suit)] <= num do return suit

    assert(false) //NOTE: This should be unreachable, is reached likely means target_card_index is invalid
    return DeckLocation(-1)
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

    board := initialise_board(&cards)

    all_cards_and_piles_texture := rl.LoadTexture("assets/all_cards_and_piles.png")
    card_back_texture := rl.LoadTexture("assets/card_back.png")

    selected_card_indices: sa.Small_Array(13, int)
    mouse_pos_on_click: rl.Vector2
    card_pos_on_click: rl.Vector2
    //TODO: Make something more descriptive than Maybe type?
    top_selected_card_location: CardLocation //nil means it came from the deck

    for !rl.WindowShouldClose() {
        
        mouse_pos := rl.GetMousePosition()

        if rl.IsMouseButtonPressed(.LEFT) {
            
            clicked_on_deck := rl.CheckCollisionPointRec(mouse_pos, rect_v(DECK_POS, CARD_TEXTURE_CARD_DIMS))
            
            if !clicked_on_deck {
                //Check if a face-up card was selected
                potential_selected_indices : sa.Small_Array(52, int)
                for card, card_index in cards {
                    if !card.face_down && rl.CheckCollisionPointRec(mouse_pos, card.rect) {
                        sa.append(&potential_selected_indices, card_index)
                    }
                }

                if sa.len(potential_selected_indices) > 0 {
                    selected_index := sa.get(potential_selected_indices, 0)
                    for card_index in sa.slice(&potential_selected_indices)[1:] {
                        if cards[card_index].z_index > cards[selected_index].z_index {
                            selected_index = card_index
                        }
                    }

                    top_selected_card_location = card_index_location(&board, selected_index)
                    switch loc in top_selected_card_location {
                    case DepotLocation:
                        for card_index in sa.slice(&board.depots[loc.depot_index])[loc.index_in_depot:] {
                            sa.append(&selected_card_indices, card_index) 
                        }
                    
                    case DrawPileLocation: 
                        sa.append(&selected_card_indices, int(loc))

                    case SuitPileLocation:
                        card_index := suit_num_to_card_index(loc, board.suit_piles[int(loc)])
                        sa.append(&selected_card_indices, card_index)
                    
                    case DeckLocation:
                        //NOTE: This case should be unreachable. If it was reached, the decks and cards have 
                        //likely gone out of sync with each other
                        assert(false)  
                    }

                    mouse_pos_on_click = mouse_pos
                    card_pos_on_click = rect_pos(cards[selected_index].rect)
                } 
            } else {
                if sa.len(board.deck) > 0 {
                    drawn_card_index := sa.pop_back(&board.deck)
                    sa.append(&board.draw_pile, drawn_card_index)
                    cards[drawn_card_index].face_down = false
                } else {
                    //Place draw pile back into deck in draw order
                    for sa.len(board.draw_pile) > 0 {
                        sa.append(&board.deck, sa.pop_back(&board.draw_pile))
                    }
                }
            }


        }

        //TODO: There's likely to be a hidden bug within here, when I tested the game crashed after moving an
        //ace into one of the suit piles, but I have yet to recreate the bug. So test in debug mode you baffoon!
        if sa.len(selected_card_indices) > 0 && rl.IsMouseButtonReleased(.LEFT) {
                
            top_selected_card := cards[sa.get(selected_card_indices, 0)]

            if sa.len(selected_card_indices) == 1 && top_selected_card.rect.y < BANNER_HEIGHT {
                for suit in Suit {
                    suit_pile_rect := rect_v(suit_pile_pos(suit), CARD_TEXTURE_CARD_DIMS)
                    if !rl.CheckCollisionRecs(top_selected_card.rect, suit_pile_rect) do continue
                    
                    top_card_same_suit := top_selected_card.suit == suit
                    top_card_is_one_above := top_selected_card.num == board.suit_piles[int(suit)] + 1

                    if top_card_same_suit && top_card_is_one_above {
                        board.suit_piles[int(suit)] = top_selected_card.num

                        switch loc in top_selected_card_location {
                        case DepotLocation:
                            sa.consume(&board.depots[loc.depot_index], sa.len(selected_card_indices))
                        
                        case DrawPileLocation:
                            sa.pop_back(&board.draw_pile)

                        case SuitPileLocation:
                            board.suit_piles[loc] -= 1

                        case DeckLocation:
                            //NOTE: This should be unreachable, is reached likely means that 
                            //top_selected_card_location is invalid
                            assert(false) 
                        }
                    }

                    break
                }
            } else {
                //TODO: Consider just going to nearest depot instead of checking for intersection?
                for depot_index in 0..<len(board.depots) {
                    depot_loc, from_depot := top_selected_card_location.(DepotLocation)
                    if from_depot && depot_loc.depot_index == depot_index do continue

                    depot_min_x := DEPOTS_START.x + DEPOT_X_OFFSET * f32(depot_index)
                    depot_max_x := depot_min_x + CARD_TEXTURE_CARD_DIMS.x
                    selected_card_min_x := top_selected_card.rect.x
                    selected_card_max_x := top_selected_card.rect.x + top_selected_card.rect.width

                    card_min_x_in_depot := selected_card_min_x >= depot_min_x && selected_card_min_x <= depot_max_x
                    card_max_x_in_depot := selected_card_max_x >= depot_min_x && selected_card_max_x <= depot_max_x
                    if card_min_x_in_depot || card_max_x_in_depot {
                        cards_differ_in_colour := false 
                        top_is_one_more := false

                        depot_len := sa.len(board.depots[depot_index])
                        if depot_len > 0 {
                            top_card_in_depot := cards[sa.get(board.depots[depot_index], depot_len - 1)]
                            cards_differ_in_colour = !same_colour(top_card_in_depot.suit, top_selected_card.suit)
                            top_is_one_more = top_card_in_depot.num - top_selected_card.num == 1
                        }

                        moving_king_to_empty_depot := top_selected_card.num == KING && depot_len == 0

                        if (cards_differ_in_colour && top_is_one_more) || moving_king_to_empty_depot {
                            for card_index in sa.slice(&selected_card_indices) {
                                sa.append(&board.depots[depot_index], card_index) 
                            }
                            switch loc in top_selected_card_location {
                                case DepotLocation:
                                    sa.consume(&board.depots[loc.depot_index], sa.len(selected_card_indices))
                                
                                case DrawPileLocation:
                                    sa.pop_back(&board.draw_pile)
                                
                                case SuitPileLocation:
                                    board.suit_piles[loc] -= 1
                                
                                case DeckLocation:
                                    //NOTE: This should be unreachable, is reached likely means that 
                                    //top_selected_card_location is invalid
                                    assert(false) 
                                }
                        }

                        break
                    }
                }
            }
            
            sa.clear(&selected_card_indices)
        }

        if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.R) {
            board = initialise_board(&cards)
            sa.clear(&selected_card_indices) //TODO: Move into initialise game? 
        }

        for &depot, depot_index in board.depots {
            for card_index, y in sa.slice(&depot) {
                card_offset := rl.Vector2{DEPOT_X_OFFSET * f32(depot_index), CARD_STACKED_Y_OFFSET * f32(y)}
                card_pos := DEPOTS_START + card_offset
                
                cards[card_index].rect = rect_v(card_pos, CARD_TEXTURE_CARD_DIMS)
                cards[card_index].z_index = y
            }

            if sa.len(depot) > 0 do cards[sa.get(depot, sa.len(depot) - 1)].face_down = false
        }

        for card_index in sa.slice(&board.deck) {
            cards[card_index].rect = rect_v(DECK_POS, CARD_TEXTURE_CARD_DIMS)
            cards[card_index].face_down = true
        }

        for card_index, z_index in sa.slice(&board.draw_pile) {
            cards[card_index].rect = rect_v(DRAW_PILE_START, CARD_TEXTURE_CARD_DIMS)
            cards[card_index].z_index = z_index
        }

        for suit in Suit {
            for card_num in ACE..=board.suit_piles[int(suit)] {
                card_index := suit_num_to_card_index(suit, card_num)
                cards[card_index].rect = rect_v(suit_pile_pos(suit), CARD_TEXTURE_CARD_DIMS)
                cards[card_index].z_index = card_num
            }
        }

        if sa.len(selected_card_indices) > 0 {
            held_card_pos := card_pos_on_click + (mouse_pos - mouse_pos_on_click)
            for card_index, y in sa.slice(&selected_card_indices) {
                cards[card_index].rect.x = held_card_pos.x 
                cards[card_index].rect.y = held_card_pos.y + CARD_STACKED_Y_OFFSET * f32(y)
                cards[card_index].z_index = 52 + y
            }
        }

        
        {
            rl.BeginDrawing()
            defer rl.EndDrawing()

            rl.ClearBackground(rl.Color{17, 128, 0, 255})

            rl.DrawRectangleV(
                rl.Vector2{},
                rl.Vector2{SCREEN_WIDTH, BANNER_HEIGHT}, rl.Color{12, 87, 0, 255}
            )


            rl.DrawTextureRec(all_cards_and_piles_texture, RESET_DECK_MARKER_TEXTURE_RECT, DECK_POS, rl.WHITE)
            
            for suit in Suit {
                rl.DrawTextureRec(
                    all_cards_and_piles_texture, 
                    suit_pile_texture_rect(suit), 
                    suit_pile_pos(suit), 
                    rl.WHITE
                )
            }

            cards_to_draw := slice.clone(cards[:], context.temp_allocator)

            compare_by_z_index :: proc (i, j: Card) -> bool { return i.z_index < j.z_index }
            slice.sort_by(cards_to_draw, compare_by_z_index)

            for card in cards_to_draw {
                rl.DrawTextureRec(
                    all_cards_and_piles_texture if !card.face_down else card_back_texture, 
                    card_texture_rect(card.suit, card.num, card.face_down), 
                    rect_pos(card.rect), 
                    rl.WHITE
                )
            }

            //rl.DrawFPS(10, 10)
        }
    }
}