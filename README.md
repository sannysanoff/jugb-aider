
this is an effort to build b.juggregator.org client using only aider.

1. started with gemini-1.5-pro-002. it generated canvas transform code with offset/scale and got lost in arithmetics.
2. switched to claude-3.5-sonnet, which tried to pick up where gemini left, but couldnt.
3. asked it to rework with matrix affine transformations, it ran from first time.
4. added networking
5. added paint optimizations

see [input_history-human.md](input_history-human.md) to see chat session (cleaned up)

watch [video](jug-video.mp4) to see app in action.

refactorint video (not reflected in history) is available (jug-2.mp4)[here].
