package main

import rl "vendor:raylib"

main :: proc() {
    
    SCREEN_WIDTH  :: 800
    SCREEN_HEIGHT :: 450

    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "solotaire")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.RAYWHITE)

        rl.DrawText("Congrats! You created your first window!", 190, 200, 20, rl.LIGHTGRAY)
    }
}