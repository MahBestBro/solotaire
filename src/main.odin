package main

import rl "vendor:raylib"

SCREEN_WIDTH  :: 1600
SCREEN_HEIGHT :: 900

//NOTE: These include the shadow around the borders 
CARD_TEXTURE_START_OFFSET :: rl.Vector2{9, 13}
CARD_TEXTURE_X_GAP :: 13
CARD_TEXTURE_Y_GAP :: 20
CARD_TEXTURE_CARD_DIMS :: rl.Vector2{109, 149}

//TODO: Better name
BANNER_HEIGHT :: 0.16 * SCREEN_HEIGHT

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

rect_v :: proc(pos: rl.Vector2, dims: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{pos.x, pos.y, dims.x, dims.y}
}

move_rect :: proc(rect: rl.Rectangle, delta: rl.Vector2) -> rl.Rectangle {
    return rl.Rectangle{rect.x + delta.x, rect.y + delta.y, rect.width, rect.height}
}

card_texture_rect :: proc(suit: Suit, number: uint) -> (tex_rect: rl.Rectangle) {
    assert(number <= KING)
    
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

    all_cards_texture := rl.LoadTexture("assets/all_cards.png")

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.Color{17, 128, 0, 255})

        rl.DrawRectangleV(
            rl.Vector2{},
            rl.Vector2{SCREEN_WIDTH, 0.16 * SCREEN_HEIGHT}, rl.Color{12, 87, 0, 255}
        )
        
        corner_offset := rl.Vector2{20.0, 20.0 + BANNER_HEIGHT}
        for suit, y in Suit {
            for num in ACE..=KING {
                x := num - 1
                card_pos := corner_offset + rl.Vector2{
                    (CARD_TEXTURE_CARD_DIMS.x + 10.0) * f32(x), 
                    (CARD_TEXTURE_CARD_DIMS.y + 10.0) * f32(y)
                }
                rl.DrawTextureRec(
                    all_cards_texture, 
                    card_texture_rect(suit, uint(num)), 
                    card_pos, 
                    rl.WHITE
                )
            }
        }

        
    }
}