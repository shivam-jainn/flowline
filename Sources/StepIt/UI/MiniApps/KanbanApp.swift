import SwiftUI
import StepItIR
import AppKit

public struct KanbanTask: Identifiable {
    public let id = UUID()
    public var title: String
    public var category: String
    public var priority: String
    public var status: String // "Todo", "Doing", "Done"
}

public struct KanbanAppView: View {
    @State private var tasks: [KanbanTask] = [
        KanbanTask(title: "Configure OpenRouter Vision Gateway", category: "Core", priority: "High", status: "Done"),
        KanbanTask(title: "Implement Rolling Buffer GIF Engine", category: "Media", priority: "High", status: "Done"),
        KanbanTask(title: "Add 1-Click Interactive Web Doc Exporter", category: "Publishing", priority: "Medium", status: "Doing"),
        KanbanTask(title: "Support Offline Ollama Llama 3.2 Vision", category: "AI", priority: "Medium", status: "Todo")
    ]
    
    @State private var newTaskTitle: String = ""
    @State private var selectedPriority: String = "Medium"
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Label("Sprint Task Board", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text("\(tasks.filter { $0.status == "Done" }.count)/\(tasks.count) Done")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // New Task Input Form
            HStack(spacing: 10) {
                TextField("Add new task...", text: $newTaskTitle)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Picker("Priority", selection: $selectedPriority) {
                    Text("Low").tag("Low")
                    Text("Medium").tag("Medium")
                    Text("High").tag("High")
                }
                .frame(width: 110)
                
                Button(action: addTask) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            
            // 3 Columns: Todo, Doing, Done
            HStack(alignment: .top, spacing: 14) {
                columnView(title: "To Do", status: "Todo", color: .gray)
                columnView(title: "In Progress", status: "Doing", color: .blue)
                columnView(title: "Completed", status: "Done", color: .green)
            }
            .padding()
        }
        .frame(width: 680, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func columnView(title: String, status: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(tasks.filter { $0.status == status }.count)")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(8)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks.filter { $0.status == status }) { task in
                        taskCard(task: task)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
    
    private func taskCard(task: KanbanTask) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title)
                .font(.system(size: 12, weight: .semibold))
            
            HStack {
                Text(task.category)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                
                // Move button
                if task.status != "Done" {
                    Button(action: { moveTask(task) }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func addTask() {
        tasks.append(KanbanTask(
            title: newTaskTitle,
            category: "General",
            priority: selectedPriority,
            status: "Todo"
        ))
        newTaskTitle = ""
    }
    
    private func moveTask(_ task: KanbanTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            if tasks[idx].status == "Todo" {
                tasks[idx].status = "Doing"
            } else if tasks[idx].status == "Doing" {
                tasks[idx].status = "Done"
            }
        }
    }
}
