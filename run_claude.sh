#!/bin/bash

PROMPT='what does this project do?'
ADDITIONAL_FLAGS="--dangerously-skip-permissions --output-format json"
MAX_RUNS=1

if ! command -v claude &> /dev/null; then
    echo "❌ Error: Claude Code is not installed: https://claude.ai/code" >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "⚠️ jq is required for JSON parsing but is not installed. Asking Claude Code to install it..." >&2
    claude -p "Please install jq for JSON parsing" --allowedTools "Bash,Read"
    if ! command -v jq &> /dev/null; then
        echo "❌ Error: jq is still not installed after Claude Code attempt." >&2
        exit 1
    fi
fi

ERROR_LOG=$(mktemp)
trap "rm -f $ERROR_LOG" EXIT

error_count=0
extra_iterations=0
successful_iterations=0
i=1

while [ $MAX_RUNS -eq 0 ] || [ $successful_iterations -lt $MAX_RUNS ]; do
    if [ $MAX_RUNS -eq 0 ]; then
        iteration_display="($i)"
    else
        total_iterations=$((MAX_RUNS + extra_iterations))
        iteration_display="($i/$total_iterations)"
    fi
    
    echo "🔄 $iteration_display Starting iteration..." >&2
    
    iteration_failed=false
    
    if ! result=$(claude -p "$PROMPT" $ADDITIONAL_FLAGS 2>$ERROR_LOG); then
        error_count=$((error_count + 1))
        extra_iterations=$((extra_iterations + 1))
        echo "❌ $iteration_display Error occurred ($error_count consecutive errors):" >&2
        cat "$ERROR_LOG" >&2
        
        if [ $error_count -ge 3 ]; then
            echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
            exit 1
        fi
        
        iteration_failed=true
    fi

    if [ "$iteration_failed" = "false" ] && [ -s "$ERROR_LOG" ]; then
        echo "⚠️  $iteration_display Warnings or errors in stderr:" >&2
        cat "$ERROR_LOG" >&2
    fi

    if [ "$iteration_failed" = "false" ] && ! echo "$result" | jq -e . >/dev/null 2>&1; then
        error_count=$((error_count + 1))
        extra_iterations=$((extra_iterations + 1))
        echo "❌ $iteration_display Error: Invalid JSON response ($error_count consecutive errors):" >&2
        echo "$result" >&2
        
        if [ $error_count -ge 3 ]; then
            echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
            exit 1
        fi
        
        iteration_failed=true
    fi

    if [ "$iteration_failed" = "false" ]; then
        is_error=$(echo "$result" | jq -r '.is_error // false')
        if [ "$is_error" = "true" ]; then
            error_count=$((error_count + 1))
            extra_iterations=$((extra_iterations + 1))
            echo "❌ $iteration_display Error in Claude Code response ($error_count consecutive errors):" >&2
            echo "$result" | jq -r '.result // .' >&2
            
            if [ $error_count -ge 3 ]; then
                echo "❌ Fatal: 3 consecutive errors occurred. Exiting." >&2
                exit 1
            fi
            
            iteration_failed=true
        fi
    fi

    if [ "$iteration_failed" = "false" ]; then
        error_count=0
        if [ $extra_iterations -gt 0 ]; then
            extra_iterations=$((extra_iterations - 1))
        fi
        
        result_text=$(echo "$result" | jq -r '.result // empty')
        if [ -n "$result_text" ]; then
            echo "$result_text"
        fi

        cost=$(echo "$result" | jq -r '.total_cost_usd // empty')
        if [ -n "$cost" ]; then
            echo "" >&2
            printf "💰 $iteration_display Cost: \$%.3f\n" "$cost" >&2
        fi

        echo "✅ $iteration_display Work completed" >&2
        successful_iterations=$((successful_iterations + 1))
    fi

    if [ $MAX_RUNS -eq 0 ] || [ $successful_iterations -lt $MAX_RUNS ]; then
        sleep 1
    fi
    
    i=$((i + 1))
done

if [ $MAX_RUNS -ne 0 ]; then
    echo "🎉 Done"
fi
