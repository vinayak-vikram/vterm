# vterm

A native iOS app for interacting with a [ROS 2](https://docs.ros.org/en/jazzy/) network from an iPhone or iPad.

Cross-compiling the ROS 2 (Jazzy) stack for iOS was easily the most challenging part of this project, and that process is documented [here](https://vinayak-vikram.github.io/posts/ros2_iphone.html).

---

## Features

- **Publish** — spin up a `std_msgs/String` publisher on any topic and send messages
- **Subscribe** — browse live topics on the network, tap one to subscribe (or type the topic), and echo the topic in real time

## Architecture

The ROS 2 C++ stack (rclcpp, rmw\_cyclonedds\_cpp, and all dependencies) is cross-compiled for iOS arm64 and bundled as static libraries under `libs/` (you will need to compile these yourself; the libraries are not provided. again, see the [blog post](https://vinayak-vikram.github.io/posts/ros2_iphone.html)). A thin C API (`rosios.h` / `rosios.cpp`) wraps rclcpp and is exposed to Swift via a bridging header.

```
vterm/
├── ROS/
│   ├── rosios.h          # C API boundary
│   ├── rosios.cpp        # rclcpp implementation
│   ├── ROSContext.swift  # singleton: rclcpp init, executor lifecycle
│   ├── ROSNode.swift     # node wrapper
│   ├── ROSPublisher.swift
│   ├── ROSSubscriber.swift
│   └── ROSSettings.swift # persisted peer config
├── ContentView.swift     # tab UI: Publish / Subscribe / Config
libs/                     # pre-built static .a files (compile yourself)
ROS2.xcconfig             # include paths and linker flags for the static libs
```

## DDS / Discovery

iOS blocks multicast sockets, so the app uses **unicast-only** CycloneDDS discovery. Add the IP address or hostname of each peer in the **Config** tab before starting. The CYCLONEDDS\_URI is constructed at runtime from these peers and the device's WiFi IP (`en0`).

## Requirements

- Xcode 15+
- iOS 17+ deployment target
- The pre-built ROS 2 Jazzy static libraries placed under `libs/` (see the blog post above for build instructions)
- Both the iOS device and the peer machine on the same WiFi network (make sure to disable cellular on the phone while running this, it will inevitably cause issues)
