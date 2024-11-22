package main

import "core:fmt"
import "core:math/rand"
import sa "core:container/small_array"
import "core:slice"

import rl "vendor:raylib"

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
//The offset from the top of the card required in order to not hide the suit and number
CARD_STACKED_Y_OFFSET :: 45.0 

NUM_BOARD_PILES :: 7

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

Card :: struct {
    suit: Suit,
    num: uint,

    z_index: int,
    face_down: bool,
    rect: rl.Rectangle //TODO: Just have pos? Or take out of struct and calculate instead
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

card_texture_rect :: proc(suit: Suit, number: uint, face_down: bool) -> (tex_rect: rl.Rectangle) {
    assert(number <= KING)
    
    if face_down {
        tex_rect = rect_v(rl.Vector2{}, CARD_TEXTURE_CARD_DIMS)
        return
    }

    row : f32
    switch (suit) {
        case .DIAMOND: row = 0.0 
        case .HEART: row = 1.0 
        case .CLUB: row = 2.0 
        case .SPADE: row = 3.0 
    }

    column := f32(number - 1)

    offset := rl.Vector2{
        CARD_TEXTURE_CARD_DIMS.x + CARD_TEXTURE_X_GAP, 
        CARD_TEXTURE_CARD_DIMS.y + CARD_TEXTURE_Y_GAP
    }

    tex_rect = rect_v(CARD_TEXTURE_START_OFFSET, CARD_TEXTURE_CARD_DIMS)
    tex_rect = move_rect(tex_rect, rl.Vector2{column * offset.x, row * offset.y})
    return
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
            cards[card_index].num = uint(num)
            cards[card_index].face_down = false
        }
    }

    initial_shuffled_card_indices : [52]int
    for &card, i in initial_shuffled_card_indices do card = i
    rand.shuffle(initial_shuffled_card_indices[:])

    //Set up main seven piles on the board
    board_card_piles : [NUM_BOARD_PILES]sa.Small_Array(20, int)
    for pile_max in 1..=NUM_BOARD_PILES {
        pile := pile_max - 1
        for y in 0..<pile_max {
            //NOTE: The first part is the sum of all previous cards using the formula for consecutive sum from 1..n
            i := (pile_max - 1) * pile_max / 2 + y
            card_index := initial_shuffled_card_indices[i]
            
            sa.append(&board_card_piles[pile], card_index)
            
            corner_offset := rl.Vector2{20.0, 20.0 + BANNER_HEIGHT}
            pile_x_offset := (SCREEN_WIDTH - 2 * corner_offset.x) / NUM_BOARD_PILES
            card_offset := rl.Vector2{pile_x_offset * f32(pile), CARD_STACKED_Y_OFFSET * f32(y)}
            card_pos := corner_offset + card_offset
            cards[card_index].rect = rect_v(card_pos, CARD_TEXTURE_CARD_DIMS)
            cards[card_index].face_down = y < pile_max - 1
        }
    }

    //Set up deck
    for i in (NUM_BOARD_PILES * (NUM_BOARD_PILES + 1) / 2)..<52 {
        card_index := initial_shuffled_card_indices[i]
        
        cards[card_index].rect = rect_v(DECK_OFFSET, CARD_TEXTURE_CARD_DIMS)
        cards[card_index].face_down = true
        cards[card_index].z_index = i
    }

    all_cards_texture := rl.LoadTexture("assets/all_cards.png")
    card_back_texture := rl.LoadTexture("assets/card_back.png")

    selected_card_index: Maybe(int)
    mouse_pos_on_click: rl.Vector2
    card_pos_on_click: rl.Vector2

    for !rl.WindowShouldClose() {
        
        mouse_pos := rl.GetMousePosition()

        if rl.IsMouseButtonPressed(.LEFT) {
            
            potential_selected_indices : sa.Small_Array(52, int)
            for card, i in cards {
                if rl.CheckCollisionPointRec(mouse_pos, card.rect) {
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
            }
        }

        if card_index, ok := selected_card_index.?; ok {
            new_card_pos := card_pos_on_click + (mouse_pos - mouse_pos_on_click)
            cards[card_index].rect.x = new_card_pos.x 
            cards[card_index].rect.y = new_card_pos.y 
        }

        if rl.IsMouseButtonUp(.LEFT) {
            selected_card_index = nil
        }

        for _, pile_index in board_card_piles {
            for card_index, z_index in sa.slice(&board_card_piles[pile_index]) {
                cards[card_index].z_index = z_index
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