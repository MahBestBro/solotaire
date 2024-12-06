package main

import "core:fmt"
import la "core:math/linalg"
import "core:math"
import "core:math/rand"
import "core:mem"
import sa "core:container/small_array"
import "core:slice"
import "core:strings"

import rl "vendor:raylib"

NUM_DEPOTS :: 7
STARTING_TOTAL_CARDS_IN_DEPOTS :: NUM_DEPOTS * (NUM_DEPOTS + 1) / 2 
MAX_CARDS_IN_DECK :: 52 - STARTING_TOTAL_CARDS_IN_DEPOTS 

SCREEN_WIDTH  :: 1600
SCREEN_HEIGHT :: 900
SCREEN_DIMS :: rl.Vector2{SCREEN_WIDTH, SCREEN_HEIGHT}

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
SIDEBAR_PAD :: 5
SIDEBAR_WIDTH :: CARD_TEXTURE_CARD_DIMS.x + 2 * SIDEBAR_PAD

DECK_POS :: rl.Vector2{SIDEBAR_PAD, SIDEBAR_PAD}
DRAW_PILE_START :: rl.Vector2{DECK_POS.x, DECK_POS.y + CARD_TEXTURE_CARD_DIMS.y + 20.0}
SUIT_PILE_START :: rl.Vector2{SCREEN_WIDTH - SIDEBAR_WIDTH + SIDEBAR_PAD, SIDEBAR_PAD}

DEPOTS_START :: rl.Vector2{SIDEBAR_WIDTH + 20.0 , 20.0}
DEPOT_X_OFFSET := (SCREEN_WIDTH - 2 * DEPOTS_START.x) / NUM_DEPOTS

CARD_DIMS :: CARD_TEXTURE_CARD_DIMS
//The offset from the top of the card required in order to not hide the suit and number
CARD_STACKED_Y_OFFSET :: 45.0 
CARD_TOTAL_MOVE_TIME_SECS :: 0.4 

BUTTON_PAD :: 10
BUTTON_WIDTH :: SIDEBAR_WIDTH - 2 * BUTTON_PAD
BUTTON_HEIGHT :: 40 

//TODO: Convert into enum?
ACE :: 1
JACK :: 11
QUEEN :: 12
KING :: 13


flip_y :: proc(v: rl.Vector2) -> rl.Vector2 {
    return rl.Vector2{v.x, -v.y}
}

rect_v :: proc(pos: rl.Vector2, dims: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{pos.x, pos.y, dims.x, dims.y}
}

rect_pos :: proc(rect: rl.Rectangle) -> rl.Vector2 {
    return rl.Vector2{rect.x, rect.y}
}

rect_dims :: proc(rect: rl.Rectangle) -> rl.Vector2 {
    return rl.Vector2{rect.width, rect.height}
}

move_rect :: proc(rect: rl.Rectangle, delta: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{rect.x + delta.x, rect.y + delta.y, rect.width, rect.height}
}

Suit :: enum {
    DIAMOND = 0,
    HEART = 1,
    CLUB = 2,
    SPADE = 3
}

same_colour :: proc(suit1: Suit, suit2: Suit) -> bool {
    both_red := (suit1 == .DIAMOND || suit1 == .HEART) && (suit2 == .DIAMOND || suit2 == .HEART)
    both_black := (suit1 == .CLUB || suit1 == .SPADE) && (suit2 == .CLUB || suit2 == .SPADE)
    return both_red || both_black
}

Card :: struct {
    face_down: bool,

    z_index: int,
    pos: rl.Vector2,

    start_pos, target_pos: rl.Vector2,
    elapsed_move_time_secs: Maybe(f32)
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

start_card_movement :: proc(card: ^Card) {
    card.start_pos = card.pos
    card.elapsed_move_time_secs = 0.0
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

CardBack :: enum {
    DEFAULT,
    BANJY,
    THARG,
    BATMAN
}

card_back_texture_rect :: proc(card_back: CardBack) -> rl.Rectangle {
    offset := rl.Vector2{
        (CARD_TEXTURE_CARD_DIMS.x + CARD_TEXTURE_X_GAP) * (5.0 + f32(card_back)), 
        (CARD_TEXTURE_CARD_DIMS.y + CARD_TEXTURE_Y_GAP) * 4.0
    }
    return rect_v(CARD_TEXTURE_START_OFFSET + offset, CARD_TEXTURE_CARD_DIMS)
}

suit_pile_pos :: proc(suit: Suit) -> rl.Vector2 {
    return SUIT_PILE_START + rl.Vector2{0.0, f32(suit) * (CARD_DIMS.y + 5.0)}
}

//NOTE: We need not do anything for draw_pile or suit_piles since they just need to be zero-initialised, which is 
//the default behaviour. 
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
            
            cards[card_index].face_down = y < depot_max - 1
            cards[card_index].pos = DECK_POS
            start_card_movement(&cards[card_index])
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
        if card_index == target_card_index do return DeckLocation(index_in_deck)
    }

    for card_index, index_in_draw_pile in sa.slice(&board.draw_pile) {
        if card_index == target_card_index do return DrawPileLocation(index_in_draw_pile)
    }

    suit, num := card_index_to_suit_num(target_card_index)
    if board.suit_piles[int(suit)] >= num do return suit

    assert(false) //NOTE: This should be unreachable, is reached likely means target_card_index is invalid
    return DeckLocation(-1)
}

CardMove :: struct {
    from: CardLocation,
    to: CardLocation,
    num_cards: int,
    card_was_revealed: bool
}

CardDraw :: struct { }

UndoAction :: union {
    CardMove,
    CardDraw
}

//TODO: Do some investigation on how big this array needs to be, or just convert it into a dynamic array
NUM_UNDOS :: 512
UndoStack :: sa.Small_Array(NUM_UNDOS, UndoAction)

UndoKind :: enum {
    UNDO,
    REDO
}

apply_undo :: proc(undo_kind: UndoKind, game: ^Game) {
    stack_to_pop := &game.undos if undo_kind == .UNDO else &game.redos
    stack_to_push := &game.redos if undo_kind == .UNDO else &game.undos
    
    switch action in sa.pop_back(stack_to_pop) {
        case CardMove: 
            cards_to_move: sa.Small_Array(13, int)

            switch to in action.to {
                case DepotLocation:
                    for card_index in sa.slice(&game.board.depots[to.depot_index])[to.index_in_depot:] {
                        sa.append(&cards_to_move, card_index)
                    }
                    for _ in 0..<action.num_cards {
                        sa.pop_back(&game.board.depots[to.depot_index])
                    }

                case SuitPileLocation:
                    assert(action.num_cards == 1)
                    suit_index := int(to)
                    sa.append(&cards_to_move, suit_num_to_card_index(to, game.board.suit_piles[suit_index]))
                    game.board.suit_piles[suit_index] -= 1
                
                case DrawPileLocation:
                    assert(undo_kind == .REDO)
                    assert(action.num_cards == 1 && sa.len(game.board.draw_pile) > 0)
                    sa.append(&cards_to_move, sa.pop_back(&game.board.draw_pile))

                case DeckLocation: 
                    assert(false)
            }

            assert(sa.len(cards_to_move) > 0 && sa.len(cards_to_move) == action.num_cards)

            switch from in action.from {
                case DepotLocation:
                    depot := &game.board.depots[from.depot_index]
                    
                    if action.card_was_revealed && undo_kind == .UNDO {
                        assert(sa.len(depot^) > 0)
                        game.cards[sa.get(depot^, sa.len(depot^) - 1)].face_down = true
                    }

                    for card_index in sa.slice(&cards_to_move) {
                        sa.append(depot, card_index)

                        start_card_movement(&game.cards[card_index])
                    }

                case SuitPileLocation:
                    assert(sa.len(cards_to_move) == 1)
                    suit_index := int(from)
                    game.board.suit_piles[suit_index] += 1 

                    card_index := suit_num_to_card_index(from, game.board.suit_piles[suit_index])
                    start_card_movement(&game.cards[card_index])
                
                case DrawPileLocation:
                    assert(sa.len(cards_to_move) == 1)
                    card_index := sa.pop_back(&cards_to_move)
                    sa.append(&game.board.draw_pile, card_index)

                    start_card_movement(&game.cards[card_index])
                
                case DeckLocation: 
                    assert(false)
            }

            sa.append(
                stack_to_push, 
                CardMove{ 
                    from = action.to, 
                    to = action.from, 
                    num_cards = action.num_cards,
                    card_was_revealed = action.card_was_revealed
                }
            )
        
        case CardDraw:
            deck_to_pop := &game.board.draw_pile if undo_kind == .UNDO else &game.board.deck 
            deck_to_push := &game.board.deck if undo_kind == .UNDO else &game.board.draw_pile 
            
            if sa.len(deck_to_pop^) > 0 {
                card_index := sa.pop_back(deck_to_pop)
                sa.append(deck_to_push, card_index) 

                start_card_movement(&game.cards[card_index])
            } else {
                //All cards have been drawn/put back, so put all of them back into the other deck
                for sa.len(deck_to_push^) > 0 {
                    card_index := sa.pop_back(deck_to_push)
                    sa.append(deck_to_pop, card_index)

                    start_card_movement(&game.cards[card_index])
                }
            }

            sa.append(stack_to_push, action)
    }
}

Game :: struct {
    cards: [52]Card,
    board: Board,    
    undos: UndoStack,
    redos: UndoStack,

    game_won: bool
}

reset_game :: proc(game: ^Game) {
    game.board = initialise_board(&game.cards)
    sa.clear(&game.undos)
    sa.clear(&game.redos)
    game.game_won = false
}

draw_button :: proc(rect: rl.Rectangle, text: string) {
    BUTTON_TEXT_SIZE :: 20.0
    BUTTON_TEXT_SPACING :: 2.0
    BUTTON_BACKGROUND_COLOUR :: rl.Color{135, 191, 126, 255}
    BUTTON_TEXT_COLOUR :: rl.WHITE
    
    rl.DrawRectangleRec(rect, BUTTON_BACKGROUND_COLOUR)
    
    text_c := strings.clone_to_cstring(text, context.temp_allocator)
    text_dims := rl.MeasureTextEx(rl.GetFontDefault(), text_c, BUTTON_TEXT_SIZE, BUTTON_TEXT_SPACING)
    rl.DrawTextEx(
        rl.GetFontDefault(), 
        text_c, 
        rect_pos(rect) + (rect_dims(rect) - text_dims) / 2.0,
        BUTTON_TEXT_SIZE,
        BUTTON_TEXT_SPACING,
        BUTTON_TEXT_COLOUR 
    )
}


main :: proc() {

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "solotaire")
    defer rl.CloseWindow()

    rl.InitAudioDevice()
    defer rl.CloseAudioDevice()

    rl.SetTargetFPS(60)

    game : Game

    sprite_sheet := rl.LoadTexture("assets/sprite_sheet.png")

    deck_shuffle_sound := rl.LoadSound("assets/deck_shuffle.wav")
    defer rl.UnloadSound(deck_shuffle_sound)

    deck_reset_sounds := [3]rl.Sound{
        rl.LoadSound("assets/deck_reset_1.wav"),
        rl.LoadSound("assets/deck_reset_2.wav"),
        rl.LoadSound("assets/deck_reset_3.wav")
    } 
    defer {
        for sound in deck_reset_sounds {
            rl.UnloadSound(sound)
        }
    }

    card_draw_sounds := [4]rl.Sound{
        rl.LoadSound("assets/card_draw_1.wav"),
        rl.LoadSound("assets/card_draw_2.wav"),
        rl.LoadSound("assets/card_draw_3.wav"),
        rl.LoadSound("assets/card_draw_4.wav")
    }
    defer {
        for sound in card_draw_sounds {
            rl.UnloadSound(sound)
        }
    }

    card_place_sounds := [5]rl.Sound{
        rl.LoadSound("assets/card_place_1.wav"),
        rl.LoadSound("assets/card_place_2.wav"),
        rl.LoadSound("assets/card_place_3.wav"),
        rl.LoadSound("assets/card_place_4.wav"),
        rl.LoadSound("assets/card_place_5.wav")
    }
    defer {
        for sound in card_place_sounds {
            rl.UnloadSound(sound)
        }
    }

    sound_index := 0

    card_back := CardBack.DEFAULT

    selected_card_indices: sa.Small_Array(13, int)
    mouse_pos_on_click: rl.Vector2
    card_pos_on_click: rl.Vector2
    top_selected_card_from: CardLocation

    t : f32 = 0.0
    
    reset_game(&game)

    for !rl.WindowShouldClose() {
        
        dt := rl.GetFrameTime()
        defer t += dt

        mouse_pos := rl.GetMousePosition()

        if rl.IsMouseButtonPressed(.LEFT) {
            
            clicked_on_deck := rl.CheckCollisionPointRec(mouse_pos, rect_v(DECK_POS, CARD_DIMS))
            
            if !clicked_on_deck {
                //Filter out candidate cards
                potential_selected_indices : sa.Small_Array(52, int)
                for card, card_index in game.cards {
                    //NOTE: Using this guard to avoid costy process of searching up card location (probs won't
                    //have a big impact, but it's cheap to do)
                    card_rect := rect_v(card.pos, CARD_DIMS)
                    if card.face_down || !rl.CheckCollisionPointRec(mouse_pos, card_rect) do continue

                    //NOTE: This makes the loop O(n^2). If that hurts performance, come up with better
                    //approach
                    card_loc := card_index_location(&game.board, card_index)
                    dp_loc, ok := card_loc.(DrawPileLocation)
                    can_be_played_from_draw_pile := !ok || int(dp_loc) == sa.len(game.board.draw_pile) - 1
                    
                    if can_be_played_from_draw_pile do sa.append(&potential_selected_indices, card_index)
                }

                if sa.len(potential_selected_indices) > 0 {
                    selected_index := sa.get(potential_selected_indices, 0)
                    for card_index in sa.slice(&potential_selected_indices)[1:] {
                        if game.cards[card_index].z_index > game.cards[selected_index].z_index {
                            selected_index = card_index
                        }
                    }
                    
                    top_selected_card_from = card_index_location(&game.board, selected_index)
                    switch loc in top_selected_card_from {
                    case DepotLocation:
                        for card_index in sa.slice(&game.board.depots[loc.depot_index])[loc.index_in_depot:] {
                            sa.append(&selected_card_indices, card_index) 
                        }
                    
                    case DrawPileLocation: 
                        sa.append(&selected_card_indices, selected_index)

                    case SuitPileLocation:
                        card_index := suit_num_to_card_index(loc, game.board.suit_piles[int(loc)])
                        sa.append(&selected_card_indices, card_index)
                    
                    case DeckLocation:
                        //NOTE: This case should be unreachable. If it was reached, the decks and cards have 
                        //likely gone out of sync with each other
                        assert(false)  
                    }

                    mouse_pos_on_click = mouse_pos
                    card_pos_on_click = game.cards[selected_index].pos
                } 
            } else {
                if sa.len(game.board.deck) > 0 {
                    drawn_card_index := sa.pop_back(&game.board.deck)
                    sa.append(&game.board.draw_pile, drawn_card_index)

                    //This does the top 3 cards of draw_pile
                    draw_pile_len := sa.len(game.board.draw_pile)
                    top_cards_start := draw_pile_len - min(3, draw_pile_len)
                    for i in top_cards_start..<draw_pile_len {
                        start_card_movement(&game.cards[sa.get(game.board.draw_pile, i)])
                    }

                    sound := rand.choice(card_draw_sounds[:])
                    rl.PlaySound(sound)
                } else {
                    //Place draw pile back into deck in draw order
                    for sa.len(game.board.draw_pile) > 0 {
                        card_index := sa.pop_back(&game.board.draw_pile)
                        sa.append(&game.board.deck, card_index)

                        start_card_movement(&game.cards[card_index])
                    }

                    sound := rand.choice(deck_reset_sounds[:])
                    rl.PlaySound(sound)
                }

                sa.append(&game.undos, CardDraw{})
                sa.clear(&game.redos)
            }
        }

        if sa.len(selected_card_indices) > 0 && rl.IsMouseButtonReleased(.LEFT) {
                
            top_selected_card_index := sa.get(selected_card_indices, 0)
            top_selected_card := game.cards[top_selected_card_index]
            top_selected_card_suit, top_selected_card_num := card_index_to_suit_num(top_selected_card_index)
            
            top_selected_card_max_x := top_selected_card.pos.x + CARD_DIMS.x

            moved_to : Maybe(CardLocation) = nil

            if sa.len(selected_card_indices) == 1 && top_selected_card_max_x > SCREEN_WIDTH - SIDEBAR_WIDTH {
                for suit in Suit {
                    suit_pile_rect := rect_v(suit_pile_pos(suit), CARD_DIMS)
                    top_selected_card_rect := rect_v(top_selected_card.pos, CARD_DIMS)
                    if !rl.CheckCollisionRecs(top_selected_card_rect, suit_pile_rect) do continue
                    
                    top_card_same_suit := top_selected_card_suit == suit
                    top_card_is_one_above := top_selected_card_num == game.board.suit_piles[int(suit)] + 1

                    if top_card_same_suit && top_card_is_one_above {
                        game.board.suit_piles[int(suit)] = top_selected_card_num
                        moved_to = SuitPileLocation(suit)
                    }
                }
            } else {
                //TODO: Consider just going to nearest depot instead of checking for intersection?
                for depot_index in 0..<len(game.board.depots) {
                    depot_loc, from_depot := top_selected_card_from.(DepotLocation)
                    if from_depot && depot_loc.depot_index == depot_index do continue

                    depot_min_x := DEPOTS_START.x + DEPOT_X_OFFSET * f32(depot_index)
                    depot_max_x := depot_min_x + CARD_DIMS.x
                    selected_card_min_x := top_selected_card.pos.x
                    selected_card_max_x := top_selected_card.pos.x + CARD_DIMS.x

                    card_min_x_in_depot := selected_card_min_x >= depot_min_x && selected_card_min_x <= depot_max_x
                    card_max_x_in_depot := selected_card_max_x >= depot_min_x && selected_card_max_x <= depot_max_x
                    if card_min_x_in_depot || card_max_x_in_depot {
                        cards_differ_in_colour := false 
                        top_is_one_more := false

                        depot_len := sa.len(game.board.depots[depot_index])
                        if depot_len > 0 {
                            top_depot_card_index := sa.get(game.board.depots[depot_index], depot_len - 1)
                            top_depot_card_suit, top_depot_card_num := card_index_to_suit_num(top_depot_card_index)
                            cards_differ_in_colour = !same_colour(top_depot_card_suit, top_selected_card_suit)
                            top_is_one_more = top_depot_card_num - top_selected_card_num == 1
                        }

                        moving_king_to_empty_depot := top_selected_card_num == KING && depot_len == 0

                        if (cards_differ_in_colour && top_is_one_more) || moving_king_to_empty_depot {
                            depot := &game.board.depots[depot_index]
                            
                            for card_index in sa.slice(&selected_card_indices) {
                                sa.append(depot, card_index) 
                            }

                            moved_to = DepotLocation{ 
                                depot_index = depot_index, 
                                index_in_depot = sa.len(depot^) - sa.len(selected_card_indices)
                            }
                        }

                        break
                    }
                }
            }
            
            if to, ok := moved_to.?; ok {
                card_was_revealed := false
                
                switch loc in top_selected_card_from {
                case DepotLocation:
                    depot := &game.board.depots[loc.depot_index]
                    sa.consume(depot, sa.len(selected_card_indices))
                    
                    //NOTE: This should work since the cards is not turned face_up until later in the game loop
                    card_was_revealed = sa.len(depot^) > 0 && game.cards[sa.get(depot^, sa.len(depot^) - 1)].face_down     
                
                case DrawPileLocation:
                    sa.pop_back(&game.board.draw_pile)

                case SuitPileLocation:
                    game.board.suit_piles[loc] -= 1

                case DeckLocation:
                    //NOTE: This should be unreachable, is reached likely means that 
                    //top_selected_card_from is invalid
                    assert(false) 
                }
                 
                sa.append(
                    &game.undos, 
                    CardMove{ 
                        from = top_selected_card_from, 
                        to = to, 
                        num_cards = sa.len(selected_card_indices),
                        card_was_revealed = card_was_revealed
                    }
                )

                sa.clear(&game.redos)
            }

            for card_index in sa.slice(&selected_card_indices) {
                start_card_movement(&game.cards[card_index])
            }
            sa.clear(&selected_card_indices)
        
            sound := rand.choice(card_place_sounds[:])
            rl.PlaySound(sound)
        }

        NUM_BUTTONS :: 3
        BUTTON_RELATIVE_Y_START :: (BUTTON_HEIGHT + BUTTON_PAD) * NUM_BUTTONS

        undo_button_rect  := rl.Rectangle{
            x = BUTTON_PAD,
            y = SCREEN_HEIGHT - BUTTON_RELATIVE_Y_START,
            width = BUTTON_WIDTH,
            height = BUTTON_HEIGHT
        }
        pressed_undo_button := 
            rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos, undo_button_rect)
        pressed_undo_keys := rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.Z)
        if (pressed_undo_button || pressed_undo_keys) && sa.len(game.undos) > 0 {
            apply_undo(.UNDO, &game)
        }

        redo_button_rect := move_rect(undo_button_rect, rl.Vector2{0.0, BUTTON_HEIGHT + BUTTON_PAD})
        pressed_redo_button := 
            rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos, redo_button_rect)
        pressed_redo_keys := rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.Y)
        if (pressed_redo_button || pressed_redo_keys) && sa.len(game.redos) > 0 {
            apply_undo(.REDO, &game)
        }

        new_game_button_rect := move_rect(redo_button_rect, rl.Vector2{0.0, BUTTON_HEIGHT + BUTTON_PAD})
        pressed_new_game_button := 
            rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mouse_pos, new_game_button_rect)
        pressed_new_game_keys := rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.R)
        if pressed_new_game_button || pressed_new_game_keys {
            reset_game(&game)
            sa.clear(&selected_card_indices)

            rl.PlaySound(deck_shuffle_sound)
        }

        if rl.IsKeyPressed(.ONE) do card_back = CardBack(0)
        if rl.IsKeyPressed(.TWO) do card_back = CardBack(1)
        if rl.IsKeyPressed(.THREE) do card_back = CardBack(2)
        if rl.IsKeyPressed(.FOUR) do card_back = CardBack(3)

        if ODIN_DEBUG && rl.IsKeyPressed(.SPACE) {
            for _, card_index in game.cards {
                start_card_movement(&game.cards[card_index])
            }
            game.game_won = true
        }

        is_face_up :: proc(card: Card) -> bool { return !card.face_down }
        if slice.all_of_proc(game.cards[:], is_face_up) && !game.game_won {
            for _, card_index in game.cards {
                start_card_movement(&game.cards[card_index])
            }
            
            game.game_won = true
        }

        for &depot, depot_index in game.board.depots {
            for card_index, y in sa.slice(&depot) {
                card_offset := rl.Vector2{DEPOT_X_OFFSET * f32(depot_index), CARD_STACKED_Y_OFFSET * f32(y)}
                
                game.cards[card_index].target_pos = DEPOTS_START + card_offset
                game.cards[card_index].z_index = y
            }

            if sa.len(depot) > 0 do game.cards[sa.get(depot, sa.len(depot) - 1)].face_down = false
        }

        for card_index in sa.slice(&game.board.deck) {
            game.cards[card_index].target_pos = DECK_POS
            game.cards[card_index].face_down = true
        }

        for card_index, z_index in sa.slice(&game.board.draw_pile) {
            game.cards[card_index].target_pos = DRAW_PILE_START
            game.cards[card_index].z_index = z_index
            game.cards[card_index].face_down = false
        }

        //Offset the top two cards so you can see the last 3 drawn cards
        if sa.len(game.board.draw_pile) > 0 {
            y_offset := min(2.0, f32(sa.len(game.board.draw_pile) - 1)) * CARD_STACKED_Y_OFFSET
            game.cards[sa.get(game.board.draw_pile, sa.len(game.board.draw_pile) - 1)].target_pos.y += y_offset
        }
        if sa.len(game.board.draw_pile) > 1 {
            y_offset := min(1.0, f32(sa.len(game.board.draw_pile) - 2)) * CARD_STACKED_Y_OFFSET
            game.cards[sa.get(game.board.draw_pile, sa.len(game.board.draw_pile) - 2)].target_pos.y += y_offset
        }

        for suit in Suit {
            for card_num in ACE..=game.board.suit_piles[int(suit)] {
                card_index := suit_num_to_card_index(suit, card_num)
                game.cards[card_index].target_pos = suit_pile_pos(suit)
                game.cards[card_index].z_index = card_num
            }
        }

        if sa.len(selected_card_indices) > 0 {
            held_card_pos := card_pos_on_click + (mouse_pos - mouse_pos_on_click)
            for card_index, y in sa.slice(&selected_card_indices) {
                game.cards[card_index].target_pos.x = held_card_pos.x 
                game.cards[card_index].target_pos.y = held_card_pos.y + CARD_STACKED_Y_OFFSET * f32(y)
                game.cards[card_index].z_index = 52 + y
            }
        }

        if game.game_won {
            WIN_X_OFFSET :: CARD_DIMS.x - 5.0
            WIN_INNER_Y_PAD :: 40.0
            WIN_INNER_Y_OFFSET :: CARD_DIMS.y + WIN_INNER_Y_PAD
            WIN_MIDDLE_Y_PAD :: 120.0
            WIN_TWO_SUIT_ROWS_HEIGHT :: 2 * CARD_DIMS.y + WIN_INNER_Y_PAD

            WIN_SCREEN_DIMS :: rl.Vector2{
                13 * WIN_X_OFFSET,
                2 * WIN_TWO_SUIT_ROWS_HEIGHT + WIN_MIDDLE_Y_PAD
            }

            WIN_ANIM_PERIOD :: 5.0
            WIN_ANIM_AMPLITUDE :: 20.0
            WIN_WAVE_FREQ :: 7.0 //NOTE: I have no idea the technical term so sorry for the bad name

            start := (SCREEN_DIMS - WIN_SCREEN_DIMS) / 2.0
            for &card, card_index in game.cards[:len(game.cards) / 2] {
                suit, num := card_index_to_suit_num(card_index)
                offset := rl.Vector2{WIN_X_OFFSET * f32(num - 1), WIN_INNER_Y_OFFSET * f32(suit)}
                
                weird_t := t + WIN_WAVE_FREQ * f32(card_index) / 13.0
                phase : f32 = 0.5 * math.PI * f32(card_index / 13) 
                anim_y_offset := WIN_ANIM_AMPLITUDE * math.sin(2 * math.PI * weird_t / WIN_ANIM_PERIOD + phase)
                card.target_pos = start + offset + rl.Vector2{0.0, anim_y_offset}
                
                card.face_down = false
                card.z_index = card_index
            }
            
            start = (SCREEN_DIMS - flip_y(WIN_SCREEN_DIMS)) / 2.0 - rl.Vector2{0.0, WIN_TWO_SUIT_ROWS_HEIGHT}
            for &card, i in game.cards[len(game.cards) / 2:] {
                card_index := i + len(game.cards) / 2
                suit, num := card_index_to_suit_num(card_index)
                offset := rl.Vector2{WIN_X_OFFSET * f32(num - 1), WIN_INNER_Y_OFFSET * (f32(suit) - 2.0)}
                
                weird_t := t + WIN_WAVE_FREQ * f32(card_index) / 13.0
                phase : f32 = 0.5 * math.PI * f32(card_index / 13)
                anim_y_offset := WIN_ANIM_AMPLITUDE * math.sin(2 * math.PI * weird_t / WIN_ANIM_PERIOD + phase)
                card.target_pos = start + offset + rl.Vector2{0.0, anim_y_offset}

                card.face_down = false
                card.z_index = card_index + len(game.cards) / 2
            }
        }

        for &card in game.cards {
            if elapsed_time, is_moving := card.elapsed_move_time_secs.?; is_moving {
                lerp_t := elapsed_time / CARD_TOTAL_MOVE_TIME_SECS
                eased_t := min(1.0 - math.pow(2.0, -10.0 * lerp_t), 1.0)
                card.pos = la.lerp(card.start_pos, card.target_pos, eased_t)
                
                new_elapsed_time := elapsed_time + dt
                if new_elapsed_time < CARD_TOTAL_MOVE_TIME_SECS {
                    card.elapsed_move_time_secs = new_elapsed_time
                } else {
                    card.elapsed_move_time_secs = nil
                }
            } else {
                card.pos = card.target_pos
            }
        }

        
        {
            rl.BeginDrawing()
            defer rl.EndDrawing()

            rl.ClearBackground(rl.Color{17, 128, 0, 255})

            SIDEBAR_COLOUR :: rl.Color{12, 87, 0, 255}

            rl.DrawRectangleV(
                rl.Vector2{},
                rl.Vector2{SIDEBAR_WIDTH, SCREEN_HEIGHT}, 
                SIDEBAR_COLOUR
            )

            rl.DrawRectangleV(
                rl.Vector2{SCREEN_WIDTH - SIDEBAR_WIDTH, 0},
                SCREEN_DIMS, 
                SIDEBAR_COLOUR
            )

            rl.DrawTextureRec(sprite_sheet, RESET_DECK_MARKER_TEXTURE_RECT, DECK_POS, rl.WHITE)
            
            for suit in Suit {
                rl.DrawTextureRec(
                    sprite_sheet, 
                    suit_pile_texture_rect(suit), 
                    suit_pile_pos(suit), 
                    rl.WHITE
                )
            }
            
            //TODO: Change font?
            if game.game_won {
                WIN_TEXT :: "You Win!"
                WIN_TEXT_SIZE :: 50.0
                WIN_TEXT_SPACING :: 4.0
                text_dims := rl.MeasureTextEx(rl.GetFontDefault(), WIN_TEXT, WIN_TEXT_SIZE, WIN_TEXT_SPACING)
                rl.DrawTextEx(
                    rl.GetFontDefault(), 
                    WIN_TEXT, 
                    (SCREEN_DIMS - text_dims) / 2.0,
                    WIN_TEXT_SIZE,
                    WIN_TEXT_SPACING,
                    rl.WHITE 
                )
            }


            KILOBYTE :: 1024

            sort_mem : [3 * KILOBYTE]byte
            sort_arena : mem.Arena
            mem.arena_init(&sort_arena, sort_mem[:])

            cards_to_draw, err := slice.clone(game.cards[:], mem.arena_allocator(&sort_arena))
            assert(err == .None)
            
            compare_by_z_index :: proc (i, j: Card) -> bool { return i.z_index < j.z_index }
            card_indices_to_draw := slice.sort_by_with_indices(
                cards_to_draw, 
                compare_by_z_index, 
                mem.arena_allocator(&sort_arena)
            )

            for card, i in cards_to_draw {
                suit, num := card_index_to_suit_num(card_indices_to_draw[i])
                texture_rect := card_texture_rect(suit, num, card.face_down)
                if card.face_down do texture_rect = card_back_texture_rect(card_back)

                rl.DrawTextureRec(sprite_sheet, texture_rect, card.pos, rl.WHITE)
            }

            draw_button(undo_button_rect, "UNDO")
            draw_button(redo_button_rect, "REDO")
            draw_button(new_game_button_rect, "NEW")

            //rl.DrawFPS(10, 10)
        }
    }
}