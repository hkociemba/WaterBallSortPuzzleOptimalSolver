# WaterBallSortPuzzleOptimalSolver
The program optimally solves a general class of puzzles which as a special case also contains well known puzzles like "Water Sort Puzzle", "Ball Sort Puzzle", "Sort Hoop", "Sort It 3D" etc. It is developed and compiled with the free Lazarus IDE (https://www.lazarus-ide.org/).
The used algorithm is a breadth first search together with a hash table with 2^32 entries (one bit per entry). Optimal solutions for the special cases mentioned above are found within less than a second but up to 14 different colors even with 6 blocks per column like in the example below the optimal solution is found within second.![ScreenShot00022](https://user-images.githubusercontent.com/27646885/119711084-67f1c300-be5f-11eb-9d24-8caf1e17d7c7.png)

You have the possibility to create random positions, to edit positions and to apply valid moves to a position. The undo function is helpfull if you try to solve the puzzle manually and you get stuck.

