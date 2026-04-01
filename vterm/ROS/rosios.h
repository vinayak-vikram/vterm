#ifndef ROSIOS_H
#define ROSIOS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// opaque handle types; all ROS objects are passed as void* across the C boundary
typedef void* rosios_node_t;
typedef void* rosios_publisher_t;
typedef void* rosios_subscription_t;
typedef void* rosios_executor_t;

// callback type for string subscriptions
// msg: null-terminated UTF-8 message data (only valid for the duration of the call)
// userdata: the pointer passed to rosios_create_subscription_string
typedef void (*rosios_string_callback_t)(const char* msg, void* userdata);

// MARK: context

// initialize rclcpp.  pass argc/argv from main (or 0/NULL for defaults)
void rosios_init(int argc, const char** argv);

// shut down rclcpp.  must be called only after all nodes/executors are destroyed
void rosios_shutdown(void);

// returns true while rclcpp is OK (not shutdown)
bool rosios_ok(void);

// MARK: node

// create a new node.  returns NULL on failure
// name: node name (!)
// namespace_: node namespace (?)
rosios_node_t rosios_create_node(const char* name, const char* namespace_);

// destroy a node previously created with rosios_create_node
void rosios_destroy_node(rosios_node_t node);

// MARK: publisher

// create a std_msgs/msg/String publisher on `topic`
// qos_depth - keep-last queue depth
// Returns NULL on failure.
rosios_publisher_t rosios_create_publisher_string(rosios_node_t node,
                                                   const char* topic,
                                                   int32_t qos_depth);

// Publish a null-terminated string message.
void rosios_publish_string(rosios_publisher_t pub, const char* msg);

// Returns the number of matched subscriptions for a publisher.
int32_t rosios_publisher_subscription_count(rosios_publisher_t pub);

// Destroy a publisher.
void rosios_destroy_publisher(rosios_publisher_t pub);

// subscription
// create a std_msgs/msg/String subscription on `topic`
// callback: called on every received message (from the executor thread)
// userdata: arbitrary pointer forwarded to callback; *ownership is NOT taken*
// returns NULL on failure
rosios_subscription_t rosios_create_subscription_string(rosios_node_t node,
                                                         const char* topic,
                                                         int32_t qos_depth,
                                                         rosios_string_callback_t callback,
                                                         void* userdata);

// destroy a subscription
void rosios_destroy_subscription(rosios_subscription_t sub);

// MARK: executor

// create a SingleThreadedExecutor.  returns NULL on failure
rosios_executor_t rosios_create_executor(void);

// add a node to the executor.
void rosios_executor_add_node(rosios_executor_t exec, rosios_node_t node);

// remove a node from the executor.
void rosios_executor_remove_node(rosios_executor_t exec, rosios_node_t node);

// spin the executor (blocking until rosios_spin_stop is called)
void rosios_spin(rosios_executor_t exec);

// process pending callbacks without blocking; timeout_ms is the maximum wait
// duration in milliseconds (0 = non-blocking poll)
void rosios_spin_some(rosios_executor_t exec, int64_t timeout_ms);

// signal a spinning executor to stop.
void rosios_spin_stop(rosios_executor_t exec);

// destroy the executor.
void rosios_destroy_executor(rosios_executor_t exec);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // ROSIOS_H
