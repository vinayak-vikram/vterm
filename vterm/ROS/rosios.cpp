// rosios.cpp; C++ implementation of the rosios C api

#include "rosios.h"

#include <atomic>
#include <memory>
#include <string>

#include <rclcpp/rclcpp.hpp>
#include <std_msgs/msg/string.hpp>

// internal wrapper structs
// all rclcpp shared_ptrs live on the heap inside these structs
// pointers to the structs are vended to Swift as opaque void*

struct ROSNode {
    rclcpp::Node::SharedPtr node;
};

struct ROSPublisher {
    rclcpp::Publisher<std_msgs::msg::String>::SharedPtr publisher;
};

struct ROSSubscription {
    rclcpp::Subscription<std_msgs::msg::String>::SharedPtr subscription;
};

struct ROSExecutor {
    std::shared_ptr<rclcpp::executors::SingleThreadedExecutor> executor;
    std::atomic<bool> stop_requested{false};
};

// MARK: context

extern "C" void rosios_init(int argc, const char** argv) {
    if (argc == 0 || argv == nullptr) {
        // rclcpp::init requires at least argc==1 with a valid program name
        // provide a synthetic argv when the caller does not pass something
        static const char* fake_argv[] = {"vterm_ios"};
        rclcpp::init(1, reinterpret_cast<char const * const *>(fake_argv));
    } else {
        rclcpp::init(argc, reinterpret_cast<char const * const *>(argv));
    }
}

extern "C" void rosios_shutdown(void) {
    rclcpp::shutdown();
}

extern "C" bool rosios_ok(void) {
    return rclcpp::ok();
}

// MARK: node

extern "C" rosios_node_t rosios_create_node(const char* name, const char* namespace_) {
    if (!name) return nullptr;

    std::string ns = (namespace_ && namespace_[0] != '\0') ? std::string(namespace_) : "";
    try {
        auto* wrapper = new ROSNode();
        wrapper->node = std::make_shared<rclcpp::Node>(std::string(name), ns);
        return static_cast<void*>(wrapper);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void rosios_destroy_node(rosios_node_t node) {
    if (!node) return;
    delete static_cast<ROSNode*>(node);
}

// MARK: publisher

extern "C" rosios_publisher_t rosios_create_publisher_string(rosios_node_t node,
                                                               const char* topic,
                                                               int32_t qos_depth) {
    if (!node || !topic) return nullptr;
    auto* n = static_cast<ROSNode*>(node);
    try {
        auto* wrapper = new ROSPublisher();
        wrapper->publisher = n->node->create_publisher<std_msgs::msg::String>(
            std::string(topic),
            static_cast<size_t>(qos_depth > 0 ? qos_depth : 10)
        );
        return static_cast<void*>(wrapper);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void rosios_publish_string(rosios_publisher_t pub, const char* msg) {
    if (!pub || !msg) return;
    auto* wrapper = static_cast<ROSPublisher*>(pub);
    auto message = std_msgs::msg::String();
    message.data = std::string(msg);
    wrapper->publisher->publish(message);
}

extern "C" void rosios_destroy_publisher(rosios_publisher_t pub) {
    if (!pub) return;
    delete static_cast<ROSPublisher*>(pub);
}

// MARK: subscription

extern "C" rosios_subscription_t rosios_create_subscription_string(
    rosios_node_t node,
    const char* topic,
    int32_t qos_depth,
    rosios_string_callback_t callback,
    void* userdata)
{
    if (!node || !topic || !callback) return nullptr;
    auto* n = static_cast<ROSNode*>(node);

    try {
        auto* wrapper = new ROSSubscription();
        // capture callback and userdata by value in the lambda
        wrapper->subscription = n->node->create_subscription<std_msgs::msg::String>(
            std::string(topic),
            static_cast<size_t>(qos_depth > 0 ? qos_depth : 10),
            [callback, userdata](const std_msgs::msg::String::SharedPtr msg) {
                callback(msg->data.c_str(), userdata);
            }
        );
        return static_cast<void*>(wrapper);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void rosios_destroy_subscription(rosios_subscription_t sub) {
    if (!sub) return;
    delete static_cast<ROSSubscription*>(sub);
}

// MARK: executor

extern "C" rosios_executor_t rosios_create_executor(void) {
    try {
        auto* wrapper = new ROSExecutor();
        wrapper->executor = std::make_shared<rclcpp::executors::SingleThreadedExecutor>();
        return static_cast<void*>(wrapper);
    } catch (...) {
        return nullptr;
    }
}

extern "C" void rosios_executor_add_node(rosios_executor_t exec, rosios_node_t node) {
    if (!exec || !node) return;
    auto* e = static_cast<ROSExecutor*>(exec);
    auto* n = static_cast<ROSNode*>(node);
    e->executor->add_node(n->node);
}

extern "C" void rosios_executor_remove_node(rosios_executor_t exec, rosios_node_t node) {
    if (!exec || !node) return;
    auto* e = static_cast<ROSExecutor*>(exec);
    auto* n = static_cast<ROSNode*>(node);
    e->executor->remove_node(n->node);
}

extern "C" void rosios_spin(rosios_executor_t exec) {
    if (!exec) return;
    auto* e = static_cast<ROSExecutor*>(exec);
    e->stop_requested.store(false);

    // spin manually so we can honor the stop flag
    while (rclcpp::ok() && !e->stop_requested.load()) {
        e->executor->spin_some(std::chrono::milliseconds(100));
    }
}

extern "C" void rosios_spin_some(rosios_executor_t exec, int64_t timeout_ms) {
    if (!exec) return;
    auto* e = static_cast<ROSExecutor*>(exec);
    auto timeout = (timeout_ms <= 0)
        ? std::chrono::nanoseconds(0)
        : std::chrono::duration_cast<std::chrono::nanoseconds>(
              std::chrono::milliseconds(timeout_ms));
    e->executor->spin_some(timeout);
}

extern "C" void rosios_spin_stop(rosios_executor_t exec) {
    if (!exec) return;
    auto* e = static_cast<ROSExecutor*>(exec);
    e->stop_requested.store(true);
    e->executor->cancel();
}

extern "C" void rosios_destroy_executor(rosios_executor_t exec) {
    if (!exec) return;
    delete static_cast<ROSExecutor*>(exec);
}
