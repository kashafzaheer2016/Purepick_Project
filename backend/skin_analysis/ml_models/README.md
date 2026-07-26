# ML Models for Skin Analysis

Place the following files from the original
`AI-Powered-Skin-Facial-Condition-Diagnosis` project here:

| File | Source |
|------|--------|
| `resnet50-dataset-test_acc_0.66959_epoch-1.pt` | `app/dataset/models/` |
| `dataset_model_classes.json` | `app/dataset/models/` |
| `haarcascade_frontalface_default.xml` | `server/` |

The `.pt` file is a PyTorch ResNet-50 model trained on 8 skin condition classes.
The `.json` file maps class indices to class labels (required by ImageAI).

> **Note:** OpenCV ships its own `haarcascade_frontalface_default.xml` so you only
> need to copy it if you want the exact same cascade used by the original app.
> The engine automatically falls back to OpenCV's built-in copy.
