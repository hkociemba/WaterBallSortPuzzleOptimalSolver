# WaterBallSortPuzzleOptimalSolver
The program optimally solves a general class of puzzles which as a special case also contains well known puzzles like "Water Sort Puzzle", "Ball Sort Puzzle", "Sort Hoop", "Sort It 3D" etc. It is developed and compiled with the free Lazarus IDE (https://www.lazarus-ide.org/).
The used algorithm resembles both A* and breadth first search. IT moreover uses an array with 2^32 elements (one bit per element) to store the 32 bit hash values of generated nodes. Optimal solutions for the special cases mentioned above are found within less than a second but up to 14 different colors even with 6 blocks per column like in the example below the optimal solution is found within seconds.![ScreenShot00022](https://user-images.githubusercontent.com/27646885/119711084-67f1c300-be5f-11eb-9d24-8caf1e17d7c7.png)

You have the possibility to create random positions, to edit positions and to apply valid moves to a position. The undo function is helpfull if you try to solve the puzzle manually and you get stuck.
A windows x64 exe file can be downloaded here:<br>
http://kociemba.org/downloads/colorsortoptimalsolver.zip

A more detailed explanation of the used algorithm is here:<br>
http://kociemba.org/themen/waterball/colorsort.html

